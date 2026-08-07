-- Switch to the U.S. English keyboard whenever Ghostty or VS Code becomes
-- the active app ("Code" is VS Code's application name).
local M = {}

local US_SOURCE_ID = "com.apple.keylayout.US"
local FORCE_US_APPS = { ["Ghostty"] = true, ["Code"] = true }

local function forceUSLayout(appName)
  if FORCE_US_APPS[appName] and hs.keycodes.currentSourceID() ~= US_SOURCE_ID then
    hs.keycodes.currentSourceID(US_SOURCE_ID)
  end
end

-- Kept in the module table so the watcher is not garbage-collected.
M.watcher = hs.application.watcher.new(function(appName, eventType, _)
  if eventType == hs.application.watcher.activated then
    forceUSLayout(appName)
  end
end)
M.watcher:start()

-- Apply on load in case one of the apps is already frontmost.
forceUSLayout(hs.application.frontmostApplication():name())

return M
