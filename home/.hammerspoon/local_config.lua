-- Machine-private settings (Chrome profiles, work URLs), loaded once for
-- every module that reads them:
--
--   local cfg = require("local_config")
--
-- They live outside this public repo, behind a git-ignored link at
-- ~/.hammerspoon/local_hammerspoon.lua (see init.lua). Only a missing link
-- is optional: anything else wrong with it would quietly turn off profile
-- routing, so it alerts and raises instead.
--
--   ~/.hammerspoon/local_hammerspoon.lua    result
--   no link (machine without private config) {}  (links open unforced)
--   link to a file that loads to a table      that table
--   dangling link, syntax or runtime error,   alert "local_config: ..." and
--   or a file that returns no table           raise; the reload stops there
local log = require("event_log").new("local_config")
local fail = require("failure").new("local_config", log)

local MODULE = "local_hammerspoon"
local path = hs.configdir .. "/" .. MODULE .. ".lua"

-- symlinkAttributes, not attributes: a link whose target is gone (Dropbox
-- not synced yet) still exists here, and is an error to report, not a
-- machine without private config.
if not hs.fs.symlinkAttributes(path) then
  log("no %s: links open in Chrome with no profile forcing", path)
  return {}
end

local ok, cfg = pcall(require, MODULE)
if not ok then
  fail(string.format("could not load %s (fix it, or remove the link): %s", path, cfg))
end
if type(cfg) ~= "table" then
  fail(string.format("%s returned a %s, not a table", path, type(cfg)))
end
log("loaded %s", path)
return cfg
