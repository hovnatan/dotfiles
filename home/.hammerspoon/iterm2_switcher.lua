-- Middle click in iTerm2 opens a picker of every iTerm2 window (picker.lua);
-- picking one (Return, or a click) brings it to front, switching Space as
-- needed. Esc, or a click elsewhere, closes it.
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
--     picker, a row per window, the most recently focused first, the
--     second row selected and under the pointer:
--                                     ~/.dotfiles
--                                     3 tabs (current)
--                                   > ai-agent: [claude]
--                                     1 tab
--          | picked
--          v
--     iterm2_api.activateWindow --"window <id>"--> iterm2_api.py
--
-- The second row is the window in front before this one, so a middle click
-- and then Return, or a left click without moving, flips between the two
-- latest, as Cmd-Tab does between apps.
-- The order is the focus history iterm2_api.py keeps since it started; a
-- window not focused since then sorts after, oldest opened first.
--
-- Asked on the up, not the down: the picker makes Hammerspoon frontmost,
-- which stops the tap, and an up after that would reach the pane, a
-- release report with no press for tmux. The list takes about 10 ms
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

local api = require("iterm2_api")
local picker = require("picker")

-- Every open and pick is logged (event_log.lua), to the file only, e.g.
--   2026-10-20T17:02:11.410Z middle click: listing windows
--   2026-10-20T17:02:11.436Z picker up: 5 windows at (612, 603)
--   2026-10-20T17:02:13.902Z picked pty-1C2B
-- The picker's own log (picker.lua) has its side: shown, closed and why.
local log
log, M.logDir = require("event_log").new("iterm2_switcher", { console = false })

-- fail() alerts and raises; guarded() runs what a timer calls (whose
-- errors go to the Console only) and alerts what no fail() did, here or in
-- iterm2_api or the picker (failure.lua).
local fail, guarded = require("failure").new("iterm2_switcher", log)

-- onPick raises, not guarded() here: the picker runs it guarded, alerts
-- what no fail() did, and gives the keyboard back to the app in front
-- before when it raised (iterm2_api.py down: nothing came forward).
M.picker = picker.new({
  onPick = function(window)
    log("picked %s", window)
    api.activateWindow(window)
  end,
  onCancel = function()
    log("picker closed, nothing picked")
  end,
})

-- A row per window, e.g.
--   { id = "<id>", title = "~/.dotfiles", detail = "3 tabs (current)" }
-- A window with no title of its own is named by its number, "window 6",
-- iTerm2's own (Cmd-Opt-6): its row changes with the order, its number not.
local function show(event, point)
  local rows = {}
  for _, window in ipairs(event.windows) do
    table.insert(rows, {
      id = window.window,
      title = window.title ~= "" and window.title or ("window " .. window.number),
      detail = string.format(
        "%d tab%s%s",
        window.tabs,
        window.tabs == 1 and "" or "s",
        window.window == event.current and " (current)" or ""
      ),
    })
  end
  -- %.0f, not %d: a click's position can be fractional (812.5), which %d
  -- raises on.
  log("picker up: %d windows at (%.0f, %.0f)", #rows, point.x, point.y)
  M.picker:show(rows, { at = point, selected = #rows >= 2 and 2 or 1 })
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

-- The picker's panel is deleted on the way out, not left to the garbage
-- collector, which may run after the new config has put up its own. The
-- hook is one global, so an earlier one is kept and called.
local previousShutdown = hs.shutdownCallback
hs.shutdownCallback = function()
  M.picker:delete()
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
