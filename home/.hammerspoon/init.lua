-- Machine-private settings (Chrome profiles, work URLs) are required as
-- "local_hammerspoon". They are not in this public repo:
-- ~/.hammerspoon/local_hammerspoon.lua is a symlink to wherever this machine
-- keeps them, created by scripts/setup_user_symlinks.sh and git-ignored --
-- the same trick as ~/.ssh/local_config. Hammerspoon already searches
-- ~/.hammerspoon/?.lua, so no package.path setup is needed here, and every
-- require of it is pcall'd so a machine without the link still loads.

-- Process-wide, and prompts on first run: hs.window/menu manipulation in
-- several modules below depends on it, so ask once here rather than from
-- whichever module happens to load first.
hs.accessibilityState(true)

require("force_us_layout")
require("url_dispatcher")
require("app_hotkeys")
require("fullscreen_apps")
-- require("meeting_focus")

-- hs CLI (`hs -c "..."`) for scripting and debugging from the shell.
-- cliInstall puts the man page in <prefix>/share/man/man1 but does not create
-- that directory; without it only `hs` installs and every later config load
-- logs "incomplete installation of 'hs' and 'hs.1'".
local cliPrefix = os.getenv("HOME") .. "/.local"
require("hs.ipc")
if not hs.ipc.cliStatus(cliPrefix) then
  for _, dir in ipairs({ "/share", "/share/man", "/share/man/man1" }) do
    hs.fs.mkdir(cliPrefix .. dir)
  end
  hs.ipc.cliUninstall(cliPrefix)
  hs.ipc.cliInstall(cliPrefix)
end
