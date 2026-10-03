-- Switch to the U.S. English keyboard whenever an app in FORCE_US_APPS
-- becomes the active app.
local M = {}

local US_SOURCE_ID = "com.apple.keylayout.US"
-- Keyed by bundle ID like the other modules: app names are localized and
-- renamable (and WhatsApp shows why they cannot be trusted at all).
local FORCE_US_APPS = {
  ["com.mitchellh.ghostty"] = true,
  ["com.googlecode.iterm2"] = true,
  ["com.microsoft.VSCode"] = true,
  -- The viewer helper, not the com.hovnatan.zathura launcher: the windows
  -- belong to the helper (scripts/macos/build_zathura_app.sh).
  ["com.hovnatan.zathura.viewer"] = true,
  -- Siri AI and the system Siri. Not the Cmd-Space panel, though campo owns
  -- it: it opens without activating campo, so no activated event fires.
  ["com.apple.campo"] = true,
  ["com.apple.Siri"] = true,
}

local function forceUSLayout(app)
  if app and FORCE_US_APPS[app:bundleID()] and hs.keycodes.currentSourceID() ~= US_SOURCE_ID then
    hs.keycodes.currentSourceID(US_SOURCE_ID)
  end
end

-- Kept in the module table so the watcher is not garbage-collected.
M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if eventType == hs.application.watcher.activated then
    forceUSLayout(app)
  end
end)
M.watcher:start()

-- Apply on load in case one of the apps is already frontmost.
forceUSLayout(hs.application.frontmostApplication())

return M
