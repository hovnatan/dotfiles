-- local_config.lua (machine-private: Chrome profiles, work URLs) lives in
-- Dropbox/Scripts/hammerspoon so it syncs across Macs without git.
for _, dir in ipairs({
  os.getenv("HOME") .. "/Library/CloudStorage/Dropbox/Scripts/hammerspoon",
  os.getenv("HOME") .. "/Dropbox/Scripts/hammerspoon",
}) do
  package.path = package.path .. ";" .. dir .. "/?.lua"
end

require("force_us_layout")
require("url_dispatcher")
require("app_hotkeys")
require("fullscreen_apps")
-- require("meeting_focus")

-- hs CLI (`hs -c "..."`) for scripting and debugging from the shell
require("hs.ipc")
hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")
