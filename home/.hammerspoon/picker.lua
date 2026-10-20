-- A list to pick from, in a panel of its own: rows in, the picked row's id
-- out. No filter field, unlike hs.chooser (which always has one), and its
-- look is ours: gruvbox, dark or light as macOS is, any size. Page and
-- styles: picker.html.
--
--   local p = picker.new({ onPick = fn(id), onCancel = fn() })
--   p:show({ { id = "<id>", title = "~/.dotfiles", detail = "3 tabs" } },
--          { at = point, selected = 2 })   row 2 selected, under the point
--
--   show --render(rows)--> picker.html --row count--> sized, placed,
--        Hammerspoon activated, shown
--   picker.html --"pick" (Return, click)--> hidden, onPick(id), which
--        brings forward what was picked; if it raises, the app in front
--        before is activated again
--   picker.html --"cancel" (Esc)--> hidden, the app in front before
--        activated again, onCancel()
--   panel loses the keyboard (a click elsewhere, Cmd-Tab) --> hidden,
--        onCancel(); nothing reactivated, the user went somewhere
--
-- Hammerspoon is the active app while the picker is up, as hs.chooser
-- does. A pick does not reactivate the app before: onPick activates what
-- was picked, and an activation first would land on the window that was in
-- front, for as long as the switch takes. iTerm2's window-name banner
-- (iterm2_window_names.lua) then named the old window, then the new one,
-- when a Space slide outlasted its 0.25s wait (2026-10-20 logs). Not a
-- nonactivating panel, which takes the keys with the other app left in
-- front: that app never learns it lost the keyboard, so hiding the panel
-- does not give it back, and the window picked came forward with no keys
-- reaching it (tried 2026-10-20).
--
-- The page is loaded once, at new(), and kept hidden between openings: a
-- webview's first load is about 100 ms (its WebKit process starting), an
-- update after that about 8 ms (2026-10-20). The price is that process,
-- about 30 MB, for as long as the picker is kept.
local M = {}
M.__index = M

local PAGE = hs.configdir .. "/picker.html"
-- Pixels, for both the page's CSS (render() sets them) and the panel's
-- height here: 2 * pad + rows * row.
local SIZES = { row = 56, pad = 6, title = 18, detail = 14 }
-- More rows than this scroll.
local MAX_ROWS = 12
-- Pixels from the panel's left edge to the pointer: inside the rows (they
-- start at `pad`), near their text, with the panel opening to the right.
local POINTER_INSET = 40
-- Of the screen's width: a long title still fits.
local WIDTH_SHARE = 0.32

-- Every opening, pick and close is logged (event_log.lua), to the file
-- only, e.g.
--   2026-10-20T19:49:08.526Z shown: 5 rows at (648, 484), 614x292, row 2 selected; in front before: com.googlecode.iterm2
--   2026-10-20T19:49:16.053Z closed: picked pty-ED0B8468-...
local log
log, M.logDir = require("event_log").new("picker", { console = false })

-- fail() alerts and raises; guarded() alerts what no fail() did, the
-- caller's (onPick, onCancel) included (failure.lua).
local fail, guarded = require("failure").new("picker", log)

-- The webview's callbacks, whose errors would go to the Console only.
local function wrap(fn)
  return function(...)
    guarded(fn, ...)
  end
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(v, hi))
end

function M.new(opts)
  local self = setmetatable({
    onPick = assert(opts.onPick, "picker.new: onPick is required"),
    onCancel = opts.onCancel or function() end,
    ready = false,
    open = false,
  }, M)

  local file = io.open(PAGE)
  if not file then
    fail("cannot read " .. PAGE)
  end
  local page = file:read("a")
  file:close()

  -- What the page sends (window.webkit.messageHandlers.picker).
  local content = hs.webview.usercontent.new("picker")
  content:setCallback(wrap(function(message)
    self:received(message.body)
  end))

  -- Above other windows and on the Space in front, a full-screen app's
  -- included (as hs.chooser is); borderless, its corners and shadow drawn
  -- by the page on a transparent window.
  local behaviors = hs.drawing.windowBehaviors
  self.view = hs.webview
    .new({ x = 0, y = 0, w = 1, h = 1 }, {}, content)
    :windowStyle({ "borderless" })
    :allowTextEntry(true)
    :transparent(true)
    :shadow(true)
    :level(hs.drawing.windowLevels.popUpMenu)
    :behavior(behaviors.moveToActiveSpace + behaviors.fullScreenAuxiliary)
    :navigationCallback(wrap(function(action, _, _, err)
      if action == "didFinishNavigation" then
        self.ready = true
        log("page loaded")
      elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
        fail(string.format("%s did not load: %s", PAGE, hs.inspect(err)))
      end
    end))
    :windowCallback(wrap(function(action, _, state)
      if action == "focusChange" and not state and self.open then
        self:close("lost the keyboard")
        self.onCancel()
      end
    end))
  self.view:html(page)
  return self
end

-- A message from the page: { action = "pick", id = "<id>" } or
-- { action = "cancel" }. One after the panel closed (a click as it lost
-- focus) is dropped: the close already answered.
function M:received(body)
  if type(body) ~= "table" or (body.action ~= "pick" and body.action ~= "cancel") then
    fail("the page sent a message this module does not know: " .. hs.inspect(body))
  end
  if not self.open then
    log("%s after closing: dropped", body.action)
    return
  end
  if body.action == "pick" then
    local previous = self:close("picked " .. tostring(body.id), false)
    -- A pick that failed brings nothing forward: the keyboard goes back.
    if not guarded(self.onPick, body.id) and previous then
      log("onPick failed: back to %s", tostring(previous:bundleID()))
      previous:activate()
    end
  else
    self:close("cancelled", true)
    self.onCancel()
  end
end

-- Hides the panel; with `giveBack`, the app in front before it (show) is
-- activated again, so its window has the keyboard: Esc leaves things as
-- they were. Returns that app, or nil.
function M:close(why, giveBack)
  self.open = false
  self.view:hide()
  local previous = self.previous
  self.previous = nil
  if giveBack and previous then
    previous:activate()
  end
  log("closed: %s%s", why, giveBack and previous and (", back to " .. tostring(previous:bundleID())) or "")
  return previous
end

-- Shows `rows` with row `opts.selected` (1-based) selected and under the
-- point `opts.at`, so a click there without moving picks it: e.g. a middle
-- click at (700, 500) with row 2 selected puts the panel's top-left at
-- (660, 410), that row's middle at the pointer. Moved in by whatever would
-- cross the screen's edge (a click near an edge), which takes the row off
-- the pointer by as much. Shown once the page has the rows, so an opening
-- never flashes the last one's.
function M:show(rows, opts)
  if not self.ready then
    fail("its page is still loading (Hammerspoon just reloaded?): try again in a moment")
  end
  if #rows == 0 then
    fail("nothing to pick from: no rows")
  end
  -- Not hs.screen.find(point): a point there is a place in the screens'
  -- arrangement ({0, 0} the primary), not a position on them.
  local at = hs.geometry.point(opts.at.x, opts.at.y)
  local screen
  for _, s in ipairs(hs.screen.allScreens()) do
    if at:inside(s:fullFrame()) then
      screen = s
    end
  end
  if not screen then
    fail(string.format("no screen at (%.0f, %.0f)", opts.at.x, opts.at.y))
  end
  local bounds = screen:frame()
  local w = math.floor(bounds.w * WIDTH_SHARE)
  local h = 2 * SIZES.pad + math.min(#rows, MAX_ROWS) * SIZES.row
  local rowMiddle = SIZES.pad + (opts.selected - 0.5) * SIZES.row
  local frame = {
    x = clamp(opts.at.x - POINTER_INSET, bounds.x, bounds.x + bounds.w - w),
    y = clamp(opts.at.y - rowMiddle, bounds.y, bounds.y + bounds.h - h),
    w = w,
    h = h,
  }

  -- JSON is a JavaScript literal: the rows reach the page as data, and it
  -- sets them as text only (picker.html).
  local data = {
    rows = rows,
    selected = opts.selected - 1,
    light = hs.host.interfaceStyle() ~= "Dark",
    sizes = SIZES,
  }
  self.view:evaluateJavaScript(
    "render(" .. hs.json.encode(data) .. ")",
    wrap(function(result, err)
      -- An error table comes either way; code 0 is none (checked 2026-10-20).
      if err and err.code ~= 0 then
        fail("the page failed to render the rows: " .. hs.inspect(err))
      end
      if result ~= #rows then
        fail(string.format("the page rendered %s rows of %d", tostring(result), #rows))
      end
      -- The app to give the keyboard back to; not Hammerspoon itself, when
      -- the picker is shown again while up.
      local front = hs.application.frontmostApplication()
      if front and front:bundleID() ~= "org.hammerspoon.Hammerspoon" then
        self.previous = front
      end
      self.view:frame(frame)
      hs.focus()
      self.view:show()
      self.open = true
      log(
        "shown: %d rows at (%.0f, %.0f), %.0fx%.0f, row %d selected; in front before: %s",
        #rows,
        frame.x,
        frame.y,
        w,
        h,
        opts.selected,
        self.previous and self.previous:bundleID() or "none"
      )
    end)
  )
end

function M:delete()
  self.view:delete()
end

return M
