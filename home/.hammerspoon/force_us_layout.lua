-- Switch to the U.S. English keyboard whenever Ghostty or VS Code becomes
-- the active app.
local M = {}

local US_SOURCE_ID = "com.apple.keylayout.US"
-- Keyed by bundle ID like the other modules: app names are localized and
-- renamable (and WhatsApp shows why they cannot be trusted at all).
local FORCE_US_APPS = {
  ["com.mitchellh.ghostty"] = true,
  ["com.microsoft.VSCode"] = true,
}

local function forceUSLayout(app)
  if app and FORCE_US_APPS[app:bundleID()]
      and hs.keycodes.currentSourceID() ~= US_SOURCE_ID then
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
