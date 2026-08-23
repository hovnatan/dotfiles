-- local_config.lua (machine-private: Chrome profiles, work URLs) lives in
-- Dropbox/Scripts/hammerspoon so it syncs across Macs without git.
for _, dir in ipairs({
  os.getenv("HOME") .. "/Library/CloudStorage/Dropbox/Scripts/hammerspoon",
  os.getenv("HOME") .. "/Dropbox/Scripts/hammerspoon",
}) do
  package.path = package.path .. ";" .. dir .. "/?.lua"
end

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
