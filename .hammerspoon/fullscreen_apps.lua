-- Open certain apps in (native) full screen, for apps with no setting of
-- their own -- VS Code has window.newWindowDimensions, WhatsApp does not.
--
-- Driven by app launches rather than hs.window.filter: WhatsApp is a Catalyst
-- app and the window filter never receives its windowCreated events. Only
-- launches are handled, so leaving full screen later is not fought.
local M = {}

-- Keyed by bundle ID: WhatsApp reports its name as "\u{200E}WhatsApp", with
-- an invisible left-to-right mark that no name comparison would match.
local FULLSCREEN_APPS = {
  ["net.whatsapp.WhatsApp"] = true,
  ["com.apple.iCal"] = true, -- Calendar
  ["com.google.Chrome"] = true,
  ["com.tinyspeck.slackmacgap"] = true, -- Slack
  ["org.zotero.zotero"] = true,
  ["com.apple.Preview"] = true,
}
local RETRY_INTERVAL = 0.5
local MAX_TRIES = 20 -- Catalyst apps can take seconds to show their window

local function fullscreenWhenReady(app, tries)
  local win = app:mainWindow()
  if win and win:isStandard() then
    win:setFullScreen(true)
  elseif tries < MAX_TRIES then
    hs.timer.doAfter(RETRY_INTERVAL, function()
      fullscreenWhenReady(app, tries + 1)
    end)
  end
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.launched
      and app and FULLSCREEN_APPS[app:bundleID()] then
    fullscreenWhenReady(app, 0)
  end
end)
M.watcher:start()

return M
