-- Global app-switching hotkeys (alt+1..5). The Chrome ones focus a specific
-- profile via Chrome's "Profiles" menu, which raises that profile's last
-- window (or opens one only if none exists) -- a --profile-directory
-- relaunch would spawn a new window on every press instead. Menu selection
-- needs the Accessibility permission; without it the hotkey still focuses
-- Chrome, just not a specific profile.
local ok, cfg = pcall(require, "local_config")
if not ok then cfg = {} end

-- Map profile directories to display names via Chrome's Local State. Read
-- once at config load -- reload the Hammerspoon config after adding or
-- renaming Chrome profiles.
local profileNames = {}
do
  local state = hs.json.read(os.getenv("HOME")
    .. "/Library/Application Support/Google/Chrome/Local State")
  local cache = state and state.profile and state.profile.info_cache or {}
  for dir, info in pairs(cache) do profileNames[dir] = info.name end
end

hs.accessibilityState(true)

-- Chrome's Profiles menu decorates titles ("Hovnatan (a@b.io)" for a
-- Local State name of "a@b.io"), so match the item by substring at press
-- time rather than by exact title.
local function selectProfileMenuItem(chrome, profileName)
  for _, m in ipairs(chrome:getMenuItems() or {}) do
    if m.AXTitle == "Profiles" then
      for _, item in ipairs(m.AXChildren and m.AXChildren[1] or {}) do
        local title = item.AXTitle or ""
        if title == profileName or title:find(profileName, 1, true) then
          return chrome:selectMenuItem({ "Profiles", title })
        end
      end
    end
  end
end

local function focusChromeProfile(profileDir)
  local chrome = hs.application.applicationsForBundleID("com.google.Chrome")[1]
  if not chrome then
    hs.task.new("/usr/bin/open", nil, {
      "-na", "Google Chrome", "--args",
      "--profile-directory=" .. (profileDir or "Default"),
    }):start()
    return
  end
  chrome:activate()
  local name = profileDir and profileNames[profileDir]
  if name then selectProfileMenuItem(chrome, name) end
end

local MOD = { "alt" }
hs.hotkey.bind(MOD, "1", function() focusChromeProfile(cfg.default_chrome_profile) end)
hs.hotkey.bind(MOD, "2", function() focusChromeProfile(cfg.work_chrome_profile) end)
hs.hotkey.bind(MOD, "3", function() hs.application.launchOrFocusByBundleID("com.tinyspeck.slackmacgap") end)
hs.hotkey.bind(MOD, "4", function() hs.application.launchOrFocusByBundleID("com.microsoft.VSCode") end)
hs.hotkey.bind(MOD, "5", function() hs.application.launchOrFocusByBundleID("com.mitchellh.ghostty") end)
