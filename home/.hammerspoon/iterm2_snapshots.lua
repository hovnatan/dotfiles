-- Every 10 minutes while iTerm2 runs, saves its windows as an ssh
-- arrangement snapshot, keeping the newest 2016 (two weeks of them):
--
--   timer, every INTERVAL s
--     |  iTerm2 not running, or the last snapshot still running -> skipped
--     v
--   scripts/iterm2_ssh_arrangement.sh snapshot   (hs.task)
--     -> ~/.local/state/iterm2_ssh_arrangements/auto-<UTC YYYYMMDD_HHMMSS>.txt
--        and all but the newest 2016 removed, once the new one is saved
--     |
--     v  exit
--   0      logged; an alert if it ends a run of failures
--   other  logged with the script's output; an alert if it starts a run
--          of failures, so one cause alerts once, not every 10 minutes.
--          Not by the error's text: it names windows key window first,
--          so one cause reads differently as the focus moves.
--
-- Bring one back beside the windows open, from any terminal:
--   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh restore auto-20261019_143000
-- or in place of them, iTerm2 quit and launched, from another terminal app:
--   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh replace auto-20261019_143000
--
-- The script's own log is one directory a day,
-- <dotfiles>/.logs/<UTC time>_iterm2_ssh_snapshot/; this module's says when
-- each ran and how it ended.
-- The timer and its failure handling are shared: snapshots.lua.
local iterm2Api = require("iterm2_api")

return require("snapshots").new({
  name = "iterm2_snapshots",
  app = "iTerm2",
  script = "iterm2_ssh_arrangement.sh",
  -- Whether iTerm2 runs, which iterm2_api.lua already tracks.
  running = function()
    return iterm2Api.itermRunning
  end,
})
