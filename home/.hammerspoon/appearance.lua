-- Run scripts/appearance.sh when macOS turns light or dark, so Claude Code's
-- theme and zathura turn with it. This module only says when: what follows
-- the appearance, and how, is the script's, which also runs by hand and at
-- install.
--
--   AppleInterfaceThemeChangedNotification     load      wake from sleep
--   (a switch by hand, or Auto at sunset)       |        (a switch slept
--                  \                            |         through posts
--                   v                           v         nothing) /
--                 settle timer, SETTLE seconds, restarted by each <-
--                                 |
--                 mode = the appearance now; the one applied? --> done
--                                 |
--                 scripts/appearance.sh <mode>   (own process)
--                                 |
--                 exit 0: applied = mode        else: alert and raise
--
-- The timer is there for two reasons: macOS posts the notification more
-- than once per switch, and the setting hs.host.interfaceStyle() reads can
-- still hold the old value when the first one arrives.
local M = {}

local SCRIPT = os.getenv("HOME") .. "/.dotfiles/scripts/appearance.sh"
local SETTLE = 0.5 -- seconds
local TIMEOUT = 30 -- seconds; the script takes about 0.1, 0.5 with zathura open

-- Every step is logged (event_log.lua), e.g.
--   2026-09-30T00:41:02.113Z dark -> light (notification)
--   2026-09-30T00:41:02.251Z appearance.sh light: done
local log
log, M.logDir = require("event_log").new("appearance")

local function fail(msg)
  log("ERROR %s", msg)
  hs.alert.show("appearance: " .. msg, 4)
  error("appearance: " .. msg)
end

M.applied = nil -- "light" | "dark": what the script last set; nil until it has
M.why = nil -- what asked for the pass under way, for the log

local function mode()
  -- "Dark" in dark mode, nil in light mode
  return hs.host.interfaceStyle() == "Dark" and "dark" or "light"
end

local function apply()
  -- One script at a time: a pass asked for while one runs waits its turn,
  -- then sees for itself whether anything is left to do.
  if M.task then
    M.timer:start()
    return
  end
  local wanted = mode()
  if wanted == M.applied then
    log("%s already (%s)", wanted, M.why)
    return
  end
  log("%s -> %s (%s)", tostring(M.applied), wanted, M.why)

  local task, timer
  local function done(code, out, err)
    -- The end of a script that was killed for taking too long: reported then.
    if M.task ~= task then
      return
    end
    M.task = nil
    timer:stop()
    if code ~= 0 then
      fail(string.format("appearance.sh %s failed (exit %d): %s%s", wanted, code, out, err))
    end
    M.applied = wanted
    log("appearance.sh %s: done", wanted)
  end
  task = hs.task.new(SCRIPT, done, { wanted })
  timer = hs.timer.doAfter(TIMEOUT, function()
    if M.task == task then
      M.task = nil
      task:terminate()
      fail("appearance.sh " .. wanted .. " took over " .. TIMEOUT .. "s")
    end
  end)
  M.task, M.taskTimer = task, timer
  task:start()
end

M.timer = hs.timer.delayed.new(SETTLE, apply)

local function ask(why)
  M.why = why
  M.timer:start()
end

-- Kept in M so they are not garbage-collected.
M.notifications = hs.distributednotifications.new(function()
  ask("notification")
end, "AppleInterfaceThemeChangedNotification")
M.notifications:start()

M.wake = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then
    ask("wake")
  end
end)
M.wake:start()

-- At load the links may be from before a switch made while Hammerspoon was
-- not running.
ask("load")

return M
