-- Flash an iTerm2 window's title over it for a moment whenever that window
-- gets focus (Cmd-`, a click, Cmd-Tab or AltTab back to iTerm2), so it is
-- clear which window you landed in. The title is iTerm2's own: the Dotfiles
-- profile's Custom Window Title, e.g. "(mbp) ~/.dotfiles", or whatever
-- Window > Edit Window Title set for that one window, e.g. a prefix
-- "work (mbp) ...".
--
--   app watcher --(iTerm2 launched / quit)--> attach / drop the AX observer
--
--   AX observer on iTerm2
--     AXFocusedWindowChanged, AXApplicationActivated / Deactivated
--        |  each event: hide any overlay now, restart the settle timer
--        v
--   SETTLE_SECONDS with no further event
--        |
--        v
--   iTerm2 frontmost, its focused window a standard one?
--        no  --> nothing (focus left iTerm2, or a sheet / panel)
--        yes --> canvas sized to win:title(), centred on the window,
--                fades out after SHOW_SECONDS
--
-- Why the settle wait: the iTerm2 windows run full screen, each in a Space
-- of its own, and a switch between them plays the Space slide, during which
-- the screen bounces old -> new -> old -> new for about 0.25s (recorded at
-- 20 fps with this module off, 2026-10-07). An overlay drawn at the first
-- focus event blinked on and off with that bounce. Shown only once focus has
-- stayed put, it appears after the slide, once.
--
-- Why not hs.window.filter: it was the first version, and after a
-- Hammerspoon reload it stopped reporting windowFocused altogether while
-- the AX observer of iterm2_bell_banners.lua, the same mechanism as here,
-- kept seeing every focus change.
--
-- Focus within a window (tab or pane switch) is not a window focus, so it
-- shows nothing: the tab bar already names the tab.
local M = {}

local ITERM2 = "com.googlecode.iterm2"
local SETTLE_SECONDS = 0.25
local SHOW_SECONDS = 2
local FADE_SECONDS = 0.2
local TEXT_SIZE = 28
local PADDING = 24 -- inside the box, around the text
local MARGIN = 40 -- between the box and the window's sides; a longer title is cut at the end
local MIN_TEXT_WIDTH = 120 -- a window narrower than this gets a box wider than itself

-- Every focus event and overlay is logged (event_log.lua), to the file only, e.g.
--   2026-10-07T14:52:10.012Z AXFocusedWindowChanged
--   2026-10-07T14:52:10.364Z window 81234: (mbp) ~/.dotfiles
local log
log, M.logDir = require("event_log").new("iterm2_window_names", { console = false })

local function hideOverlay()
  if M.timer then
    M.timer:stop()
    M.timer = nil
  end
  if M.overlay then
    M.overlay:delete()
    M.overlay = nil
  end
end

local function show(win)
  local title = win:title()

  -- A window that has just opened can report "" for a moment; an empty box
  -- says nothing, so it is logged and skipped.
  if title == "" then
    log("window %s: empty title, nothing shown", tostring(win:id()))
    return
  end
  log("window %s: %s", tostring(win:id()), title)

  -- Size the text first (one line, cut at the end when it is wider than the
  -- window allows, but never below MIN_TEXT_WIDTH: a window 100 px wide would
  -- otherwise give a negative width), then centre the box on the window's
  -- frame. Canvas and window frames share one coordinate space across screens.
  local overlay = hs.canvas.new({ x = 0, y = 0, w = 1, h = 1 })
  overlay:appendElements({
    type = "rectangle",
    action = "fill",
    fillColor = { white = 0.1, alpha = 0.85 },
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  }, {
    type = "text",
    text = title,
    textFont = hs.styledtext.defaultFonts.boldSystem.name,
    textSize = TEXT_SIZE,
    textColor = { white = 1 },
    textAlignment = "center",
    textLineBreak = "truncateTail",
  })
  local text = overlay:minimumTextSize(2, title)
  local frame = win:frame()
  local w = math.min(text.w, math.max(MIN_TEXT_WIDTH, frame.w - 2 * (MARGIN + PADDING)))
  overlay[2].frame = { x = PADDING, y = PADDING, w = w, h = text.h }
  overlay:frame({
    x = frame.x + (frame.w - w) / 2 - PADDING,
    y = frame.y + (frame.h - text.h) / 2 - PADDING,
    w = w + 2 * PADDING,
    h = text.h + 2 * PADDING,
  })

  -- Above every window, full-screen Spaces included (canJoinAllSpaces; any
  -- focus event hides it again, so it never trails into another Space), and
  -- never in the way of a click (a canvas takes no mouse events unless asked).
  overlay:level(hs.canvas.windowLevels.overlay)
  overlay:behavior({ "canJoinAllSpaces", "transient" })
  overlay:show(FADE_SECONDS)
  M.overlay = overlay
  M.timer = hs.timer.doAfter(SHOW_SECONDS, function()
    M.timer = nil
    M.overlay = nil
    overlay:delete(FADE_SECONDS)
  end)
end

-- Focus has stayed put for SETTLE_SECONDS: show the focused iTerm2 window,
-- if iTerm2 still has focus and it is a real window, not a sheet or panel.
local function settled()
  local app = hs.application.get(ITERM2)
  if not (app and app:isFrontmost()) then
    return
  end
  local win = app:focusedWindow()
  if win and win:isStandard() then
    show(win)
  end
end

M.settleTimer = hs.timer.delayed.new(SETTLE_SECONDS, settled)

-- Observer and watcher, kept in M so they are not garbage-collected. The
-- observer follows iTerm2 through relaunches by way of the app watcher.
local function watchITerm2(app)
  if M.observer then
    M.observer:stop()
    M.observer = nil
  end
  if not app then
    M.settleTimer:stop()
    hideOverlay()
    return
  end
  M.observer = hs.axuielement.observer.new(app:pid())
  M.observer:callback(function(_, _, event)
    log("%s", event)
    hideOverlay()
    M.settleTimer:start()
  end)
  local root = hs.axuielement.applicationElement(app)
  M.observer:addWatcher(root, "AXFocusedWindowChanged")
  M.observer:addWatcher(root, "AXApplicationActivated")
  M.observer:addWatcher(root, "AXApplicationDeactivated")
  M.observer:start()
end

M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if not app or app:bundleID() ~= ITERM2 then
    return
  end
  if eventType == hs.application.watcher.launched then
    log("iTerm2 launched (pid %d)", app:pid())
    watchITerm2(app)
  elseif eventType == hs.application.watcher.terminated then
    log("iTerm2 quit")
    watchITerm2(nil)
  end
end)
M.watcher:start()

local iterm = hs.application.applicationsForBundleID(ITERM2)[1]
log("loaded: iTerm2 %s", iterm and ("running (pid " .. iterm:pid() .. ")") or "not running")
watchITerm2(iterm)

return M
