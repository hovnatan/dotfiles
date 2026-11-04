-- Every 10 minutes while Ghostty runs, saves which tmux sessions its windows
-- hold as an arrangement snapshot, keeping the newest 2016 (two weeks):
--
--   timer, every 10 minutes (snapshots.lua)
--     |  Ghostty not running, or the last snapshot still running -> skipped
--     v
--   scripts/ghostty_tmux_arrangement.sh snapshot
--     -> ~/.local/state/ghostty_tmux_arrangements/auto-<UTC YYYYMMDD_HHMMSS>.txt
--
-- Bring one back beside the windows open, from any terminal:
--   ~/.dotfiles/scripts/ghostty_tmux_arrangement.sh restore auto-20261104_143000
--
-- The first run asks macOS to let Hammerspoon control Ghostty; until that is
-- allowed each snapshot fails, and the alert says where to allow it.
local GHOSTTY = "com.mitchellh.ghostty"

return require("snapshots").new({
  name = "ghostty_snapshots",
  app = "Ghostty",
  script = "ghostty_tmux_arrangement.sh",
  running = function()
    return hs.application.get(GHOSTTY) ~= nil
  end,
})
