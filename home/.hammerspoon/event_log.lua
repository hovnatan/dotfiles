-- Per-module event log, the repo's rule for anything that runs on its own
-- (AGENTS.md). Hammerspoon keeps no lasting record itself: its Console is
-- in memory and capped at 100,000 characters, and its unified-log
-- breadcrumbs are redacted to "<private>".
--
--   local log = require("event_log").new("iterm2_keys", { console = false })
--   log("Ctrl-U: scroll up (%s)", reason)
--   -> <dotfiles>/.logs/20260929_200749_iterm2_keys/events.log
--      2026-09-29T20:08:09.975Z Ctrl-U: scroll up (main screen, alt-screen check 17 ms)
--
-- One directory per module per load, i.e. per Hammerspoon reload, named by
-- its UTC load time (the repo's .logs/<timestamp>_<name>/ convention;
-- ignored through home/.config/git/ignore). The file is line-buffered, so
-- it can be read while Hammerspoon runs. Each line is also printed to the
-- Console as "<name>: <message>" unless `console = false`, for modules that
-- log per keypress and would crowd everything else out of it.
local M = {}

-- The dotfiles checkout is where ~/.hammerspoon points; anything else is an
-- install this repo does not know, so it raises.
local function repoRoot()
  local configDir = hs.fs.pathToAbsolute(hs.configdir)
  local repo = configDir:match("^(.*)/home/%.hammerspoon$")
  if not repo then
    error("event_log: ~/.hammerspoon resolves to " .. configDir .. ", not <dotfiles>/home/.hammerspoon")
  end
  return repo
end

-- A log function for `name`, plus the directory it writes to.
function M.new(name, opts)
  local console = not (opts and opts.console == false)
  local repo = repoRoot()
  local dir = repo .. "/.logs/" .. os.date("!%Y%m%d_%H%M%S") .. "_" .. name
  for _, d in ipairs({ repo .. "/.logs", dir }) do
    if hs.fs.attributes(d, "mode") ~= "directory" then
      assert(hs.fs.mkdir(d))
    end
  end
  local file = assert(io.open(dir .. "/events.log", "a"))
  file:setvbuf("line")

  local function log(fmt, ...)
    local msg = string.format(fmt, ...)
    local now = hs.timer.secondsSinceEpoch()
    local stamp = os.date("!%Y-%m-%dT%H:%M:%S", math.floor(now)) .. string.format(".%03dZ", math.floor(now % 1 * 1000))
    file:write(stamp, " ", msg, "\n")
    if console then
      print(name .. ": " .. msg)
    end
  end
  return log, dir
end

return M
