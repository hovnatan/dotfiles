-- Global app-switching hotkeys (alt+1..5). The Chrome ones focus a specific
-- profile via Chrome's "Profiles" menu, which raises that profile's last
-- window (or opens one only if none exists) -- a --profile-directory
-- relaunch would spawn a new window on every press instead. Menu selection
-- needs the Accessibility permission (requested in init.lua); without it the
-- hotkey still focuses Chrome, just not a specific profile.
local chrome = require("chrome")
local ok, cfg = pcall(require, "local_hammerspoon")
if not ok then cfg = {} end

-- Chrome's Profiles menu decorates titles ("Hovnatan (a@b.io)" for a Local
-- State name of "a@b.io"), so the item has to be found by substring. The
-- walk is cached per profile: the no-callback form of getMenuItems() blocks
-- Hammerspoon while it serializes Chrome's entire menu bar (History,
-- Bookmarks, ...) over accessibility, while selectMenuItem with a table
-- path goes straight to the item.
local menuTitles = {} -- profile directory -> decorated Profiles menu title

-- Read per walk, i.e. only on a cache miss (it is one small JSON file), so
-- a profile rename resolves without a config reload.
local function profileName(profileDir)
  local state = hs.json.read(os.getenv("HOME")
    .. "/Library/Application Support/Google/Chrome/Local State")
  local info = state and state.profile and state.profile.info_cache
  return info and info[profileDir] and info[profileDir].name
end

local function findMenuTitle(app, profileDir)
  local name = profileName(profileDir)
  if not name then return nil end
  for _, menu in ipairs(app:getMenuItems() or {}) do
    if menu.AXTitle == "Profiles" then
      for _, item in ipairs(menu.AXChildren and menu.AXChildren[1] or {}) do
        local title = item.AXTitle or ""
        if title:find(name, 1, true) then return title end
      end
      return nil
    end
  end
end

-- Cached title first; on a miss (or after a profile rename) walk once more.
local function selectProfile(app, profileDir)
  if menuTitles[profileDir]
      and app:selectMenuItem({ "Profiles", menuTitles[profileDir] }) then
    return
  end
  menuTitles[profileDir] = nil
  local title = findMenuTitle(app, profileDir)
  if title and app:selectMenuItem({ "Profiles", title }) then
    menuTitles[profileDir] = title
  end
end

local function focusChromeProfile(profileDir)
  local app = chrome.get()
  if not app then
    chrome.launchWithProfile(profileDir)
    return
  end
  app:activate()
  if profileDir then selectProfile(app, profileDir) end
end

local MOD = { "alt" }
hs.hotkey.bind(MOD, "1", function() focusChromeProfile(cfg.default_chrome_profile) end)
hs.hotkey.bind(MOD, "2", function() focusChromeProfile(cfg.work_chrome_profile) end)
hs.hotkey.bind(MOD, "3", function() hs.application.launchOrFocusByBundleID("com.tinyspeck.slackmacgap") end)
hs.hotkey.bind(MOD, "4", function() hs.application.launchOrFocusByBundleID("com.microsoft.VSCode") end)
hs.hotkey.bind(MOD, "5", function() hs.application.launchOrFocusByBundleID("com.mitchellh.ghostty") end)
