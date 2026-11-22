-- Night Shift is turned off for IINA, so a film is not tinted warm, and
-- given back to its schedule afterwards:
--
--   IINA launched, or open at load --> night_shift.swift off
--   IINA quit                      --> night_shift.swift resume
--
-- `off` turns Night Shift off if it is on. `resume` turns it on if its
-- schedule (System Settings > Displays > Night Shift) has it on at that
-- minute, and leaves it off otherwise. Nothing is remembered from launch to
-- quit: what the quit does depends on the schedule alone, so a Hammerspoon
-- reload mid-film loses nothing, and Night Shift turned off by hand for a
-- film is back on after it. With no schedule it stays off after IINA.
--
-- Only the launch turns it off: the schedule starting while IINA is open
-- (a film running through sunset) turns it on as usual.
local M = {}

local IINA = "com.colliderli.iina"
local SCRIPT = os.getenv("HOME") .. "/.dotfiles/scripts/macos/night_shift.swift"
local TIMEOUT = 30 -- seconds; the script takes about 0.4

-- Every run is logged with what the script answered (event_log.lua), e.g.
--   2026-11-22T05:20:11.113Z off (IINA launched): was on: turned off
--   2026-11-22T07:02:40.530Z resume (IINA quit): turned on (sunset to sunrise, and it is night)
local log
log, M.logDir = require("event_log").new("iina_night_shift")
local fail, guarded = require("failure").new("iina_night_shift", log)

M.pending = nil -- { verb, why }: the run asked for while another was under way

local function run()
  -- One script at a time, so a quit right after a launch cannot have its
  -- `resume` finish before the launch's `off`. Only the latest one asked
  -- for waits: each verb sets the state whatever it was.
  if M.task or not M.pending then
    return
  end
  local verb, why = table.unpack(M.pending)
  M.pending = nil

  local task, timer
  local function done(code, out, err)
    -- The end of a script that was killed for taking too long: reported then.
    if M.task ~= task then
      return
    end
    M.task = nil
    timer:stop()
    if code ~= 0 then
      fail(string.format("night_shift.swift %s failed (exit %d): %s%s", verb, code, out, err))
    end
    log("%s (%s): %s", verb, why, (out:gsub("%s+$", "")))
    run()
  end
  task = hs.task.new(SCRIPT, function(...)
    guarded(done, ...)
  end, { verb })
  timer = hs.timer.doAfter(TIMEOUT, function()
    guarded(function()
      if M.task == task then
        M.task = nil
        task:terminate()
        fail("night_shift.swift " .. verb .. " took over " .. TIMEOUT .. "s")
      end
    end)
  end)
  M.task, M.taskTimer = task, timer
  if not task:start() then
    M.task = nil
    timer:stop()
    fail("could not start " .. SCRIPT .. " " .. verb)
  end
end

local function ask(verb, why)
  M.pending = { verb, why }
  run()
end

-- Kept in M so it is not garbage-collected.
M.watcher = hs.application.watcher.new(function(_, event, app)
  guarded(function()
    if not app or app:bundleID() ~= IINA then
      return
    end
    if event == hs.application.watcher.launched then
      ask("off", "IINA launched")
    elseif event == hs.application.watcher.terminated then
      ask("resume", "IINA quit")
    end
  end)
end)
M.watcher:start()

if hs.application.get(IINA) then
  ask("off", "IINA open at load")
end

return M
