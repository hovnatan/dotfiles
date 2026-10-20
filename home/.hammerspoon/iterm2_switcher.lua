-- Middle click in iTerm2 opens a picker of every iTerm2 window; picking one
-- (click it, or type to filter and Return) brings it to front, switching
-- Space as needed. Esc closes it.
--
--   app watcher --(iTerm2 frontmost?)--> start / stop the tap, keep its pid
--
--   middle button, no modifiers held
--     down: pointer over an iTerm2 window?  no  --> unchanged, and its
--          | yes: swallowed, as are its drags     drags and up
--          |      and up, so none reaches the pane
--          v
--     up: iterm2_api.listWindows --"list"--> iterm2_api.py
--          | "windows" event, within REPLY_SECONDS, else alerted
--          v
--     hs.chooser at the click, in macOS's light or dark, a row per window,
--     the most recently focused first, the second row selected:
--                                     ~/.dotfiles
--                                     3 tabs (current)
--                                   > ai-agent: [claude]
--                                     1 tab
--          | picked
--          v
--     iterm2_api.activateWindow --"window <id>"--> iterm2_api.py
--
-- The second row is the window in front before this one, so a middle click
-- and Return flips between the two latest, as Cmd-Tab does between apps.
-- The order is the focus history iterm2_api.py keeps since it started; a
-- window not focused since then sorts after, oldest opened first.
--
-- Asked on the up, not the down: the picker makes Hammerspoon frontmost,
-- which stops the tap, and an up after that would reach the pane, a
-- release report with no press for tmux. The list takes about 25 ms
-- (2026-10-20), a click holds the button longer.
--
-- This takes the middle click from iTerm2 itself over its windows: its own
-- binding pasted there (Settings > Pointer), and a pane with mouse reporting
-- on (tmux) got it as a click report. Option-middle and the like still go
-- through.
--
-- Why the Python API, not AppleScript or hs.window: the windows run full
-- screen, each in a Space of its own, which Hammerspoon cannot list (it
-- sees the current Space's), and AppleScript took 1.3s for 5 windows and
-- their tabs, a round trip per property (2026-10-20). iterm2_api.py holds
-- the layout already.
local M = {}

local ITERM2 = "com.googlecode.iterm2"
local TYPES = hs.eventtap.event.types
local BUTTON = hs.eventtap.event.properties.mouseEventButtonNumber
local MIDDLE = 2
-- A reply later than this is alerted and dropped (iterm2_api.lua): a stuck
-- iterm2_api.py would otherwise pop the picker up long after the click,
-- over whatever is in front by then.
local REPLY_SECONDS = 1
local HAMMERSPOON = "org.hammerspoon.Hammerspoon"

local api = require("iterm2_api")

-- Every open and pick is logged (event_log.lua), to the file only, e.g.
--   2026-10-20T17:02:11.410Z middle click: listing windows
--   2026-10-20T17:02:11.436Z picker up: 5 windows
--   2026-10-20T17:02:13.902Z picked pty-1C2B: ai-agent: [claude]
local log
log, M.logDir = require("event_log").new("iterm2_switcher", { console = false })

-- Raises its message as is (level 0, no position), and keeps it, so
-- guarded() can tell one already alerted from any other.
local function fail(msg)
  log("ERROR %s", msg)
  M.lastFailure = "iterm2_switcher: " .. msg
  hs.alert.show(M.lastFailure, 4)
  error(M.lastFailure, 0)
end

-- Runs fn, alerting an error it raises that neither fail() here nor
-- iterm2_api's has alerted yet. For what runs where an error reaches no
-- one: a timer's goes to the Console only, and iterm2_api only logs its
-- callers'.
local function guarded(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and err ~= M.lastFailure and err ~= api.lastFailure then
    pcall(fail, "unexpected error: " .. tostring(err))
  end
end

M.chooser = hs.chooser.new(function(choice)
  if not choice then
    log("picker closed, nothing picked")
    return
  end
  log("picked %s: %s", choice.window, choice.text)
  api.activateWindow(choice.window)
end)

-- A fixed share of the screen's width, so a long title still fits; tall
-- enough for every window without scrolling, up to MAX_ROWS.
M.chooser:width(32)
local MAX_ROWS = 12

-- The chooser does not follow macOS's appearance, and its text colours do
-- not follow its own background (hs.chooser:bgDark), so both are set from
-- the appearance at each opening. The text is gruvbox's, as Ghostty's and
-- nvim's themes (home/.config/ghostty/config): fg and gray, dark and light.
-- The background can only be the chooser's dark or light blur: it has no
-- colour or font size of its own.
local THEMES = {
  dark = { bg = true, fg = { hex = "#ebdbb2" }, sub = { hex = "#a89984" } },
  light = { bg = false, fg = { hex = "#3c3836" }, sub = { hex = "#7c6f64" } },
}

local function applyTheme()
  local theme = hs.host.interfaceStyle() == "Dark" and THEMES.dark or THEMES.light
  M.chooser:bgDark(theme.bg)
  M.chooser:fgColor(theme.fg)
  M.chooser:subTextColor(theme.sub)
end

-- Its top-left corner at the click, moved in by whatever would cross the
-- screen's edge (a click near the bottom or right). Its size is read from
-- its window once shown, as it depends on the row count and the screen:
-- 480x304 for 5 rows at 25% of a 1920-wide screen (2026-10-20).
--
-- The window is looked up among Hammerspoon's own, by its exact title: a
-- search of every app's would be an accessibility walk of them all at each
-- click, and would match any title holding "chooser" (a browser tab on
-- hs.chooser). A hidden chooser has no window there, so the one shown is
-- the only one (both checked 2026-10-20).
local function chooserWindow()
  local found = {}
  for _, win in ipairs(hs.application.get(HAMMERSPOON):allWindows()) do
    if win:title() == "Chooser" then
      table.insert(found, win)
    end
  end
  if #found ~= 1 then
    fail(
      string.format(
        "%d Hammerspoon windows titled Chooser after showing the picker, expected 1, cannot place it"
          .. " (leftovers of a crash? quit and reopen Hammerspoon)",
        #found
      )
    )
  end
  return found[1]
end

local function placeAt(point)
  M.chooser:show(point)
  local win = chooserWindow()
  local frame, screen = win:frame(), hs.screen.find(point) or hs.screen.mainScreen()
  local bounds = screen:frame()
  local x = math.max(bounds.x, math.min(frame.x, bounds.x + bounds.w - frame.w))
  local y = math.max(bounds.y, math.min(frame.y, bounds.y + bounds.h - frame.h))
  if x ~= frame.x or y ~= frame.y then
    win:setTopLeft(hs.geometry.point(x, y))
  end
end

-- A row per window, e.g.
--   { text = "~/.dotfiles", subText = "3 tabs (current)", window = "<id>" }
-- A window with no title of its own is named by its number, "window 6",
-- iTerm2's own (Cmd-Opt-6): its row changes with the order, its number not.
local function show(event, point)
  local choices = {}
  for _, window in ipairs(event.windows) do
    table.insert(choices, {
      text = window.title ~= "" and window.title or ("window " .. window.number),
      subText = string.format(
        "%d tab%s%s",
        window.tabs,
        window.tabs == 1 and "" or "s",
        window.window == event.current and " (current)" or ""
      ),
      window = window.window,
    })
  end
  -- %.0f, not %d: a click's position can be fractional (812.5), which %d
  -- raises on.
  log("picker up: %d windows at (%.0f, %.0f)", #choices, point.x, point.y)
  M.chooser:choices(choices)
  -- What was typed at the last opening stays in the chooser (checked
  -- 2026-10-20): left, it would filter this one, and row 2 would not be
  -- the window before.
  M.chooser:query("")
  M.chooser:rows(math.min(#choices, MAX_ROWS))
  applyTheme()
  placeAt(point)
  -- After showing: show selects the first row.
  if #choices >= 2 then
    M.chooser:selectedRow(2)
  end
end

local function listAndShow(point)
  log("middle click: listing windows")
  api.listWindows(REPLY_SECONDS, function(event)
    guarded(show, event, point)
  end)
end

-- A hung app answers no accessibility call, and the default wait is seconds
-- on Hammerspoon's main thread, inside the tap; a healthy one answers in
-- about a millisecond. The system-wide element's time limit is every
-- element's in Hammerspoon (Apple's AXUIElementSetMessagingTimeout), so it
-- is set for this one call and put back after (0: the default); nothing
-- else runs in between, on the one thread.
local SYSTEM = hs.axuielement.systemWideElement()
local AX_SECONDS = 0.2

-- iTerm2's pid while the tap runs (update below), for overITerm2.
local itermPid

-- Whether the click is over iTerm2: the pid of the element under it. On a
-- fullscreen iTerm2 that is always so; a windowed one can leave another
-- app's window under the pointer, whose middle click stays its own.
local function overITerm2(event)
  local pos = event:location()
  SYSTEM:setTimeout(AX_SECONDS)
  local ok, element, err = pcall(SYSTEM.elementAtPosition, SYSTEM, pos.x, pos.y)
  SYSTEM:setTimeout(0)
  if not ok then
    error(element, 0)
  end
  if not element then
    fail(string.format("no accessibility element under the pointer at (%.0f, %.0f): %s", pos.x, pos.y, tostring(err)))
  end
  return element:pid() == itermPid
end

-- Whether the middle button's down was swallowed, so its drags and up go
-- the same way: any of them reaching the pane alone would be a stray
-- report to tmux, a motion or release with no press.
local swallowed = false

local function onOtherMouse(event)
  if event:getProperty(BUTTON) ~= MIDDLE then
    return false
  end
  local kind = event:getType()
  if kind == TYPES.otherMouseDown then
    swallowed = next(event:getFlags()) == nil and overITerm2(event)
    return swallowed
  end
  if kind == TYPES.otherMouseDragged or not swallowed then
    return swallowed
  end
  swallowed = false

  -- Asked after the tap returns, and kept in M so the timer is not
  -- garbage-collected first: the click is already swallowed.
  local point = event:location()
  M.listTimer = hs.timer.doAfter(0, function()
    guarded(listAndShow, point)
  end)
  return true
end

M.tap = hs.eventtap.new({ TYPES.otherMouseDown, TYPES.otherMouseDragged, TYPES.otherMouseUp }, onOtherMouse)

local function update(app)
  if app and app:bundleID() == ITERM2 then
    itermPid = app:pid()
    M.tap:start()
  else
    M.tap:stop()
    -- A button held across the switch: its up went to the other app.
    swallowed = false
  end
end

-- A chooser still open when Hammerspoon reloads outlives the reload: its
-- window stays on screen, and nothing can reach it any more to close it
-- (tested 2026-10-20: one shown before hs.reload() was still listed after,
-- with a new one besides). So it is closed on the way out: hidden, then
-- deleted, as delete() alone leaves an open chooser's window on screen
-- (same test). The hook is one global, so an earlier one is kept and called.
local previousShutdown = hs.shutdownCallback
hs.shutdownCallback = function()
  M.chooser:hide()
  M.chooser:delete()
  if previousShutdown then
    previousShutdown()
  end
end

-- Kept in the module table so the watcher is not garbage-collected.
M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if eventType == hs.application.watcher.activated then
    update(app)
  end
end)
M.watcher:start()

-- Apply on load in case iTerm2 is already frontmost.
update(hs.application.frontmostApplication())

return M
