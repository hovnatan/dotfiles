-- What a terminal's snapshot module is made of: a timer running its
-- arrangement script's "snapshot" every 10 minutes while the app runs.
--
--   iterm2_snapshots.lua   ghostty_snapshots.lua     name, app, script, running
--            |                    |
--            +---------+----------+
--                      v
--   snapshots.new(opts)
--     timer, every INTERVAL s, guarded
--       |  the app not running, or the last snapshot still running -> skipped
--       v
--     scripts/<opts.script> snapshot   (hs.task)
--       |
--       v  exit
--     0      logged; an alert if it ends a run of failures
--     other  logged with the script's output; an alert if it starts a run
--            of failures, so one cause alerts once, not every 10 minutes
--
-- Each has its own event log, <dotfiles>/.logs/<UTC time>_<opts.name>/.
local M = {}

local INTERVAL = 600 -- seconds between snapshots
-- Seconds before a snapshot still running is killed: a save takes a few,
-- most of it one ssh per host; one past this is an ssh that hangs, and
-- would hold off every later snapshot.
local TIMEOUT = 300
local HOME = os.getenv("HOME")
-- Hammerspoon's PATH is launchd's, without the Nix profile: bash there is
-- macOS's 3.2, and uv is missing.
local BASH = HOME .. "/.nix-profile/bin/bash"
local REPO = hs.fs.pathToAbsolute(hs.configdir):match("^(.*)/home/%.hammerspoon$")
  or error("snapshots: ~/.hammerspoon is not <dotfiles>/home/.hammerspoon")

-- The line that says how the script ended: its "ERROR: ..." line, else its
-- last, without the time stamp, which the module's own log line carries.
--   "2026-10-19T19:52:01Z ERROR: window 2 ...: tab 3 has 2 panes"
--     -> "ERROR: window 2 ...: tab 3 has 2 panes"
local function outcome(output)
  local last
  for line in output:gmatch("[^\n]+") do
    line = line:gsub("^%d%d%d%d%-%d%d%-%d%dT[%d:]+Z ", "")
    if line:match("^ERROR: ") then
      return line
    end
    last = line
  end
  return last or "(no output)"
end

-- opts: name (of the event log and alerts), app (for the "skipped" line),
-- script (in scripts/), running (whether the app runs now).
function M.new(opts)
  local S = {}
  local script = REPO .. "/scripts/" .. opts.script

  local log
  log, S.logDir = require("event_log").new(opts.name)

  -- guarded() runs each tick; see S.timer below.
  local _, guarded = require("failure").new(opts.name, log)

  -- Whether the last snapshot failed: the next failure is then no news.
  S.failing = false

  local function alert(msg)
    hs.alert.show(opts.name .. ": " .. msg, 6)
  end

  local function onExit(code, out, err)
    if S.killTimer then
      S.killTimer:stop()
    end
    S.task = nil
    if code == 0 then
      log("snapshot saved: %s", outcome(out))
      if S.failing then
        alert("snapshots are saved again")
        S.failing = false
      end
      return
    end

    local output = out .. err
    for line in output:gmatch("[^\n]+") do
      log("  %s", line)
    end
    local why = outcome(output)
    log("snapshot failed (exit %d): %s", code, why)
    if not S.failing then
      alert(string.format("snapshot failed: %s (log: %s)", why, S.logDir))
    end
    S.failing = true
  end

  function S.snapshot()
    if not opts.running() then
      log("skipped: %s is not running", opts.app)
      return
    end
    if S.task then
      log("skipped: the last snapshot (pid %d) is still running", S.task:pid())
      return
    end

    local task = hs.task.new(BASH, onExit, { script, "snapshot" })
    local env = task:environment()
    env.PATH = HOME .. "/.nix-profile/bin:" .. env.PATH
    task:setEnvironment(env)
    if not task:start() then
      log("could not start %s", script)
      alert("could not start " .. script .. " (is bash in the Nix profile?)")
      return
    end
    S.task = task
    log("snapshot started (pid %d)", task:pid())

    -- terminate() still calls onExit, which logs and alerts the kill.
    S.killTimer = hs.timer.doAfter(TIMEOUT, function()
      if S.task == task then
        log("snapshot still running after %ds: killed", TIMEOUT)
        task:terminate()
      end
    end)
  end

  -- Guarded, because hs.timer.doEvery stops for good when its callback raises,
  -- with the error in the Console alone: snapshots stopped silently that way
  -- on 2026-11-02, for 38 hours. An error now costs one snapshot, and alerts
  -- and logs what went wrong.
  S.timer = hs.timer.doEvery(INTERVAL, function()
    guarded(S.snapshot)
  end)
  log("loaded: a snapshot every %ds", INTERVAL)

  return S
end

return M
