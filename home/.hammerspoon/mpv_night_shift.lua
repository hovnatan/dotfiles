-- Night Shift is turned off for mpv, so a film is not tinted warm, and
-- given back to its schedule afterwards. An mpv launch starts a check every
-- CHECK seconds, which runs for as long as an mpv is open:
--
--   an mpv is open, first check that finds one --> night_shift.swift off
--   none is open any more                      --> night_shift.swift resume
--
-- The check, not the launch, turns it off, so a run that is over at once
-- (`mpv --version`, a script probing a file) leaves the screen alone. The
-- check, not mpv's quit, gives it back, because an mpv without a window is a
-- background app to macOS and is told as no quit at all, however it ends.
-- The price is that the tint leaves up to CHECK seconds into a film and
-- returns up to CHECK seconds after it.
--
-- mpv is a process per player window, each an app of the same bundle id
-- (started from a terminal too), so "open" is any of them.
--
-- `off` turns Night Shift off if it is on. `resume` turns it on if its
-- schedule (System Settings > Displays > Night Shift) has it on at that
-- minute, and leaves it off otherwise, so Night Shift turned off by hand for
-- a film is back on after it. With no schedule it stays off after mpv.
--
-- `off` is asked once for a run of open mpvs: the schedule starting while
-- mpv is open (a film running through sunset) turns it on as usual.
local M = {}

local MPV = "io.mpv"
local SCRIPT = os.getenv("HOME") .. "/.dotfiles/scripts/macos/night_shift.swift"
local TIMEOUT = 30 -- seconds; the script takes about 0.4
local CHECK = 2 -- seconds

-- Every run is logged with what the script answered (event_log.lua), e.g.
--   2026-11-22T05:20:11.113Z off (mpv open): was on: turned off
--   2026-11-22T07:02:40.530Z resume (no mpv left): turned on (sunset to sunrise, and it is night)
local log
log, M.logDir = require("event_log").new("mpv_night_shift")
local fail, guarded = require("failure").new("mpv_night_shift", log)

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

local function mpvOpen()
  return #hs.application.applicationsForBundleID(MPV) > 0
end

M.held = false -- `off` was asked for the mpv open now

local check
local function arm()
  M.checkTimer = hs.timer.doAfter(CHECK, function()
    guarded(check)
  end)
end

check = function()
  M.checkTimer = nil
  local open = mpvOpen()
  -- Armed before asking: a script that fails raises, and the checks go on.
  if open then
    arm()
  end
  if open and not M.held then
    M.held = true
    ask("off", "mpv open")
  elseif not open and M.held then
    M.held = false
    ask("resume", "no mpv left")
  elseif not open then
    log("left alone: mpv was gone within %d s of its launch", CHECK)
  end
end

-- Kept in M so it is not garbage-collected.
M.watcher = hs.application.watcher.new(function(_, event, app)
  guarded(function()
    if not app or app:bundleID() ~= MPV then
      return
    end
    -- An mpv started from a terminal is told as `launching` alone.
    local launch = event == hs.application.watcher.launching or event == hs.application.watcher.launched
    if launch and not M.checkTimer then
      arm()
    end
  end)
end)
M.watcher:start()

-- A reload mid-film: no launch is coming to start the checks.
if mpvOpen() then
  M.held = true
  ask("off", "mpv open at load")
  arm()
end

return M
