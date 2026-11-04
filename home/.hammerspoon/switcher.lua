-- Middle click over a terminal's window opens a picker of its windows
-- (picker.lua); picking one (Return, or a click) brings it to front. Esc,
-- or a click elsewhere, closes it.
--
--   iterm2_switcher.lua   ghostty_switcher.lua     name, bundle, list, activate
--            |                    |
--            +---------+----------+
--                      v
--   switcher.new(opts)
--
--   app watcher --(the app frontmost?)--> start / stop the tap, keep its pid
--
--   middle button, no modifiers held
--     down: pointer over the app's window?  no  --> unchanged, and its
--          | yes: swallowed, as are its drags     drags and up
--          |      and up, so none reaches the pane
--          v
--     up: opts.list(show)
--          v
--     picker, a row per window, the window in front first, the second row
--     selected and under the pointer:
--                                     ~/.dotfiles
--                                     3 tabs (current)
--                                   > ai-agent: [claude]
--                                     1 tab
--          | picked
--          v
--     opts.activate(id)
--
-- The second row is the window in front before this one, so a middle click
-- and then Return, or a left click without moving, flips between the two
-- latest, as Cmd-Tab does between apps. opts.list gives the rows in that
-- order; how it knows the order is the terminal's own matter.
--
-- Asked on the up, not the down: the picker makes Hammerspoon frontmost,
-- which stops the tap, and an up after that would reach the pane, a
-- release report with no press for tmux.
--
-- This takes the middle click from the app itself over its windows: its own
-- binding (a paste), and a pane with mouse reporting on (tmux), which got it
-- as a click report. Option-middle and the like still go through.
local M = {}

local TYPES = hs.eventtap.event.types
local BUTTON = hs.eventtap.event.properties.mouseEventButtonNumber
local MIDDLE = 2

local picker = require("picker")

-- A hung app answers no accessibility call, and the default wait is seconds
-- on Hammerspoon's main thread, inside the tap; a healthy one answers in
-- about a millisecond. The system-wide element's time limit is every
-- element's in Hammerspoon (Apple's AXUIElementSetMessagingTimeout), so it
-- is set for this one call and put back after (0: the default); nothing
-- else runs in between, on the one thread.
local SYSTEM = hs.axuielement.systemWideElement()
local AX_SECONDS = 0.2

-- opts:
--   name      its event log and its alerts, e.g. "iterm2_switcher"
--   bundle    the app's bundle id
--   list      fn(show): calls show(rows) once the windows are known, rows as
--             picker.lua's, the window in front first; it runs show guarded
--   activate  fn(id): brings the window picked to front
-- Returns S, with S.picker, S.tap, S.watcher (kept so none is collected),
-- S.logDir, S.log, S.guarded for what opts.list runs on its own timers, and
-- S.fail for what opts' functions find wrong.
function M.new(opts)
  local S = {}

  -- Every open and pick is logged (event_log.lua), to the file only, e.g.
  --   2026-10-20T17:02:11.410Z middle click: listing windows
  --   2026-10-20T17:02:11.436Z picker up: 5 windows at (612, 603)
  --   2026-10-20T17:02:13.902Z picked pty-1C2B
  -- The picker's own log (picker.lua) has its side: shown, closed and why.
  local log
  log, S.logDir = require("event_log").new(opts.name, { console = false })
  S.log = log

  -- fail() alerts and raises; guarded() runs what a timer calls (whose
  -- errors go to the Console only) and alerts what no fail() did, here or in
  -- opts' functions or the picker (failure.lua).
  local fail, guarded = require("failure").new(opts.name, log)
  S.fail, S.guarded = fail, guarded

  -- onPick raises, not guarded() here: the picker runs it guarded, alerts
  -- what no fail() did, and gives the keyboard back to the app in front
  -- before when it raised (the terminal's end down: nothing came forward).
  S.picker = picker.new({
    onPick = function(window)
      log("picked %s", window)
      opts.activate(window)
    end,
    onCancel = function()
      log("picker closed, nothing picked")
    end,
  })

  local function listAndShow(point)
    log("middle click: listing windows")
    opts.list(function(rows)
      -- %.0f, not %d: a click's position can be fractional (812.5), which
      -- %d raises on.
      log("picker up: %d windows at (%.0f, %.0f)", #rows, point.x, point.y)
      S.picker:show(rows, { at = point, selected = #rows >= 2 and 2 or 1 })
    end)
  end

  -- The app's pid while the tap runs (update below), for overApp.
  local appPid

  -- Whether the click is over the app: the pid of the element under it. On
  -- a fullscreen window that is always so; a windowed one can leave another
  -- app's window under the pointer, whose middle click stays its own.
  local function overApp(event)
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
    return element:pid() == appPid
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
      swallowed = next(event:getFlags()) == nil and overApp(event)
      return swallowed
    end
    if kind == TYPES.otherMouseDragged or not swallowed then
      return swallowed
    end
    swallowed = false

    -- Asked after the tap returns, and kept in S so the timer is not
    -- garbage-collected first: the click is already swallowed.
    local point = event:location()
    S.listTimer = hs.timer.doAfter(0, function()
      guarded(listAndShow, point)
    end)
    return true
  end

  S.tap = hs.eventtap.new({ TYPES.otherMouseDown, TYPES.otherMouseDragged, TYPES.otherMouseUp }, onOtherMouse)

  local function update(app)
    if app and app:bundleID() == opts.bundle then
      appPid = app:pid()
      S.tap:start()
    else
      S.tap:stop()
      -- A button held across the switch: its up went to the other app.
      swallowed = false
    end
  end

  -- The picker's panel is deleted on the way out, not left to the garbage
  -- collector, which may run after the new config has put up its own. The
  -- hook is one global, so an earlier one is kept and called.
  local previousShutdown = hs.shutdownCallback
  hs.shutdownCallback = function()
    S.picker:delete()
    if previousShutdown then
      previousShutdown()
    end
  end

  S.watcher = hs.application.watcher.new(function(_, eventType, app)
    if eventType == hs.application.watcher.activated then
      update(app)
    end
  end)
  S.watcher:start()

  -- Apply on load in case the app is already frontmost.
  update(hs.application.frontmostApplication())

  return S
end

return M
