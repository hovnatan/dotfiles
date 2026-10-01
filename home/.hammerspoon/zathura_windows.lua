-- Cmd-` and Cmd-Shift-` between Zathura windows. macOS cannot do it alone:
-- Cmd-` cycles the windows of one app, and Zathura.app
-- (scripts/macos/build_zathura_app.sh) starts a viewer process per document,
-- each an app of its own with a single window.
--
--   app watcher --(a viewer frontmost?)--> start / stop the key-down tap
--
--   key down: Cmd-` (step +1) / Cmd-Shift-` (step -1), swallowed
--     pgrep -x zathura              viewer pids, sorted: { 971, 67291 }
--          |
--          v
--     which one is AXFrontmost      971, the 1st
--          |  + step, wrapping
--          v
--     activate that process         67291; its one window comes forward
--
-- The order is by pid: arbitrary, but fixed while the windows stay open, so
-- repeated presses visit every window once before coming round.
--
-- Taking Cmd-` from the viewer loses nothing: with one window, the system's
-- own Cmd-` has nothing to switch to there.
--
-- Why a tap, not hs.hotkey: AltTab holds Cmd-` too, as a Carbon hotkey for
-- its "active app" panel, which by pid shows a viewer's one window. A key
-- the tap swallows never reaches that hotkey (tested 2026-10-01: the panel
-- stays closed), and the tap registers nothing, so AltTab is left alone.
-- An hs.hotkey won over AltTab's too, but broke it: an AltTab that started
-- while the hotkey was registered had no working Cmd-` in any app until it
-- was restarted (Cmd-Tab still worked; same test).
--
-- Why pgrep and pids: hs.application.applicationsForBundleID() does list the
-- viewers, but each with pid -1, and such an object can be neither activated
-- nor asked whether it is frontmost. One made from the real pid
-- (applicationForPID) can. Likewise app:isFrontmost() stays false for a
-- viewer, where the accessibility attribute AXFrontmost is right (Hammerspoon
-- 1.1.1, macOS 27, 2026-10-01).
--
-- Not handled: a minimized viewer. Activating it is expected to bring no
-- window forward, where the system's Cmd-` would skip it (untested: the
-- viewers here run full screen, which cannot be minimized).
local M = {}

-- Both come from build_zathura_app.sh: the bundle id of Helpers/Zathura.app,
-- and the process name its launcher sets (argv[0], which is what macOS's
-- pgrep -x compares).
local VIEWER = "com.hovnatan.zathura.viewer"
local PGREP = "/usr/bin/pgrep -x zathura"

-- A viewer that is busy or hung answers no accessibility call, and the
-- default wait is seconds, on Hammerspoon's main thread, where every other
-- module's keys wait with it. A healthy viewer answers in under 1 ms
-- (0.3-0.6 measured); past the limit the read is an error.
local AX_TIMEOUT = 0.2 -- seconds

local BACKTICK = hs.keycodes.map["`"]
local AUTOREPEAT = hs.eventtap.event.properties.keyboardEventAutorepeat

-- Every press is logged (event_log.lua), to the file only: a line per
-- keypress would crowd the Console. E.g.
--   2026-10-01T09:58:12.431Z Cmd-`: 971 -> 67291 (2 viewers)
local log
log, M.logDir = require("event_log").new("zathura_windows", { console = false })

local function fail(msg)
  log("ERROR %s", msg)
  error("zathura_windows: " .. msg)
end

-- Pids of the running viewers, ascending. A zathura started from a terminal
-- has no bundle and is left out: it is not part of the app.
local function viewerPids()
  local out, _, _, rc = hs.execute(PGREP)
  -- pgrep exits 0 on a match and 1 on none; anything else is its own failure.
  if rc ~= 0 and rc ~= 1 then
    fail(string.format("%s failed (exit %s): %s", PGREP, tostring(rc), out))
  end
  local pids = {}
  for match in out:gmatch("%d+") do
    local pid = tonumber(match)
    -- nil for a process that ended since pgrep saw it.
    local app = hs.application.applicationForPID(pid)
    if app and app:bundleID() == VIEWER then
      pids[#pids + 1] = pid
    end
  end
  table.sort(pids)
  return pids
end

-- Whether viewer `pid` is the frontmost app: true or false, or nil and why
-- when it gave no answer (hung, or gone since pgrep saw it).
local function isFrontmost(pid)
  local viewer = hs.axuielement.applicationElementForPID(pid)
  if not viewer then
    return nil, "no accessibility element (process gone?)"
  end
  viewer:setTimeout(AX_TIMEOUT)
  local frontmost, err = viewer:attributeValue("AXFrontmost")
  if type(frontmost) ~= "boolean" then
    return nil, string.format("no answer in %.1f s (%s)", AX_TIMEOUT, tostring(err))
  end
  return frontmost
end

local function viewerIsFrontmost()
  local app = hs.application.frontmostApplication()
  return app ~= nil and app:bundleID() == VIEWER
end

-- The tap runs only while a viewer is frontmost. Re-read on every watcher
-- event, not taken from the event's app: when the last viewer closes, what
-- matters is whatever is frontmost now, possibly nothing.
local function update()
  if viewerIsFrontmost() then
    M.tap:start()
  else
    M.tap:stop()
  end
end

-- Bring forward the viewer `step` places after the frontmost one (+1 or -1).
-- With a single viewer that is the viewer itself: nothing moves.
local function cycle(key, step)
  local pids = viewerPids()
  local current
  local silent = {} -- "971: no answer in 0.2 s (...)"
  for i, pid in ipairs(pids) do
    local frontmost, why = isFrontmost(pid)
    if frontmost then
      current = i
      break
    elseif frontmost == nil then
      silent[#silent + 1] = pid .. ": " .. why
    end
  end

  -- No frontmost viewer found. Three different states, told apart so that
  -- only a broken setup raises:
  --   the tap is stale      no viewer is frontmost any more (the last one
  --                         closed with no other app activated): stop it
  --   nothing recognised    a viewer is frontmost, yet none is listed or
  --                         one does not answer: raise
  --   a switch in flight    two quick presses: the old viewer has resigned,
  --                         the new one is not active yet: skip this press
  if not current then
    if not viewerIsFrontmost() then
      update()
      log("%s: no viewer frontmost, tap stopped", key)
    elseif #pids == 0 then
      fail(
        string.format(
          "%s pressed with a Zathura viewer frontmost, but %s finds no process "
            .. "with bundle %s. If scripts/macos/build_zathura_app.sh changed "
            .. "the helper's bundle id or the launcher's argv[0], or the Nix "
            .. "zathura no longer keeps that argv[0], update VIEWER or PGREP here",
          key,
          PGREP,
          VIEWER
        )
      )
    elseif #silent > 0 then
      fail(string.format("%s: cannot tell which viewer is frontmost; hung? %s", key, table.concat(silent, "; ")))
    else
      log("%s: no viewer is frontmost yet (a switch in flight), skipped", key)
    end
    return
  end

  local target = pids[(current - 1 + step) % #pids + 1]
  local app = hs.application.applicationForPID(target)
  if not (app and app:activate()) then
    fail(string.format("%s: could not activate viewer %d", key, target))
  end
  log("%s: %d -> %d (%d viewers)", key, pids[current], target, #pids)
end

-- A held key does not repeat: each viewer here is full screen on a Space of
-- its own, so a repeat every 30 ms would queue Space switches faster than
-- they animate. The repeats are swallowed all the same, or they would reach
-- AltTab.
local function onKeyDown(event)
  if event:getKeyCode() ~= BACKTICK then
    return false
  end
  local flags = event:getFlags()
  local key, step
  if flags:containExactly({ "cmd" }) then
    key, step = "Cmd-`", 1
  elseif flags:containExactly({ "cmd", "shift" }) then
    key, step = "Cmd-Shift-`", -1
  else
    return false
  end
  if event:getProperty(AUTOREPEAT) == 0 then
    cycle(key, step)
  end
  return true
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, onKeyDown)

-- Kept in the module table so the watcher is not garbage-collected.
local WATCHED = {
  [hs.application.watcher.activated] = true,
  [hs.application.watcher.deactivated] = true,
  [hs.application.watcher.terminated] = true,
}
M.watcher = hs.application.watcher.new(function(_, eventType)
  if WATCHED[eventType] then
    update()
  end
end)
M.watcher:start()

-- Apply on load in case a viewer is already frontmost.
update()

return M
