-- Every 10 minutes while iTerm2 runs, saves its windows as an ssh
-- arrangement snapshot, keeping the newest 144 (a day of them):
--
--   timer, every INTERVAL s
--     |  iTerm2 not running, or the last snapshot still running -> skipped
--     v
--   scripts/iterm2_ssh_arrangement.sh snapshot   (hs.task)
--     -> ~/.local/state/iterm2_ssh_arrangements/auto-<UTC YYYYMMDD_HHMMSS>.txt
--        and all but the newest 144 removed, once the new one is saved
--     |
--     v  exit
--   0      logged; an alert if it ends a run of failures
--   other  logged with the script's output; an alert if it starts a run
--          of failures, so one cause alerts once, not every 10 minutes.
--          Not by the error's text: it names windows key window first,
--          so one cause reads differently as the focus moves.
--
-- Bring one back from an iTerm2 tab:
--   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh restore auto-20261019_143000
--
-- The script's own log is one directory a day,
-- <dotfiles>/.logs/<UTC time>_iterm2_ssh_snapshot/; this module's says when
-- each ran and how it ended.
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
  or error("iterm2_snapshots: ~/.hammerspoon is not <dotfiles>/home/.hammerspoon")
local SCRIPT = REPO .. "/scripts/iterm2_ssh_arrangement.sh"

local log
log, M.logDir = require("event_log").new("iterm2_snapshots")
-- Whether iTerm2 runs, which iterm2_api.lua already tracks.
local iterm2Api = require("iterm2_api")

-- Whether the last snapshot failed: the next failure is then no news.
M.failing = false

local function alert(msg)
  hs.alert.show("iterm2_snapshots: " .. msg, 6)
end

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

local function onExit(code, out, err)
  if M.killTimer then
    M.killTimer:stop()
  end
  M.task = nil
  if code == 0 then
    log("snapshot saved: %s", outcome(out))
    if M.failing then
      alert("snapshots are saved again")
      M.failing = false
    end
    return
  end

  local output = out .. err
  for line in output:gmatch("[^\n]+") do
    log("  %s", line)
  end
  local why = outcome(output)
  log("snapshot failed (exit %d): %s", code, why)
  if not M.failing then
    alert(string.format("snapshot failed: %s (log: %s)", why, M.logDir))
  end
  M.failing = true
end

function M.snapshot()
  if not iterm2Api.itermRunning then
    log("skipped: iTerm2 is not running")
    return
  end
  if M.task then
    log("skipped: the last snapshot (pid %d) is still running", M.task:pid())
    return
  end

  local task = hs.task.new(BASH, onExit, { SCRIPT, "snapshot" })
  local env = task:environment()
  env.PATH = HOME .. "/.nix-profile/bin:" .. env.PATH
  task:setEnvironment(env)
  if not task:start() then
    log("could not start %s", SCRIPT)
    alert("could not start " .. SCRIPT .. " (is bash in the Nix profile?)")
    return
  end
  M.task = task
  log("snapshot started (pid %d)", task:pid())

  -- terminate() still calls onExit, which logs and alerts the kill.
  M.killTimer = hs.timer.doAfter(TIMEOUT, function()
    if M.task == task then
      log("snapshot still running after %ds: killed", TIMEOUT)
      task:terminate()
    end
  end)
end

M.timer = hs.timer.doEvery(INTERVAL, M.snapshot)
log("loaded: a snapshot every %ds", INTERVAL)

return M
