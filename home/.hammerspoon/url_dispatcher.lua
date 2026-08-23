-- URL dispatcher: Hammerspoon is the default browser; Google Cloud links,
-- work URLs, Slack's own domains and anything clicked in a work app (Slack)
-- open in the work Chrome profile, everything else in the default one. Only
-- links from outside Chrome hit this.
--
-- Chrome profile directories map to accounts and work URLs name the
-- employer, so both live outside the repo in local_config.lua (in
-- Dropbox/Scripts/hammerspoon; see init.lua for the search path):
--   return {
--     work_chrome_profile = "...",  -- e.g. "Default", "Profile 1"
--     default_chrome_profile = "...",
--     work_url_prefixes = { "https://github.com/someorg" },  -- optional
--   }
-- Without it, links open in Chrome with no profile forcing.
local chrome = require("chrome")
local M = {}

local ok, cfg = pcall(require, "local_config")
if not ok then cfg = {} end

local GCLOUD_HOSTS = {
  ["console.cloud.google.com"] = true,
  ["console.developers.google.com"] = true,
  ["shell.cloud.google.com"] = true,
}

-- gcloud CLI auth flows: accounts.google.com serves every Google login, so
-- only claim it when the OAuth scope includes cloud-platform (true for both
-- gcloud auth login and application-default login).
local function isGcloudAuth(host, url)
  return host == "accounts.google.com" and url:find("cloud-platform", 1, true) ~= nil
end

-- Hosts that are work whatever the source app, matched on the registrable
-- domain so every subdomain counts (app.slack.com, <workspace>.slack.com,
-- files.slack.com). Not employer-identifying, so unlike work_url_prefixes
-- these can live in the repo.
local WORK_HOST_SUFFIXES = { "slack.com" }

local function isWorkHost(host)
  if not host then return false end
  for _, suffix in ipairs(WORK_HOST_SUFFIXES) do
    if host == suffix or host:sub(-(#suffix + 1)) == "." .. suffix then
      return true
    end
  end
  return false
end

-- Apps whose links are work links regardless of the URL, so a colleague's
-- link on a domain we have never heard of still lands in the work profile.
local WORK_SOURCE_BUNDLES = {
  ["com.tinyspeck.slackmacgap"] = true, -- Slack
}

-- Which app opened the URL. hs.application.frontmostApplication() cannot
-- answer this: LaunchServices activates Hammerspoon to deliver the URL, so by
-- callback time we are frontmost ourselves (verified - it reports
-- org.hammerspoon.Hammerspoon, never the clicking app, despite LSUIElement).
-- Track activations instead and remember the last app that was not us.
-- Seeded from the current frontmost app: after a reload the watcher has seen
-- no activation yet, and Slack is often already frontmost (that is where the
-- link is about to be clicked), so nil here would misroute the first link.
-- M.watcher roots the watcher in package.loaded; one held only by a module
-- local is garbage collected and silently stops.
local sourceApp

local function rememberSource(app)
  local bundle = app and app:bundleID()
  if bundle and bundle ~= hs.processInfo.bundleID then sourceApp = bundle end
end

rememberSource(hs.application.frontmostApplication())

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated then rememberSource(app) end
end)
M.watcher:start()

local function isWorkSourceApp()
  return WORK_SOURCE_BUNDLES[sourceApp] ~= nil
end

local function isWorkURL(url)
  local lower = url:lower()
  for _, prefix in ipairs(cfg.work_url_prefixes or {}) do
    if lower:sub(1, #prefix) == prefix:lower() then return true end
  end
  return false
end

local function openInChrome(url, profile)
  if profile then
    chrome.launchWithProfile(profile, url, true)
  else
    hs.urlevent.openURLWithBundle(url, chrome.BUNDLE_ID)
  end
end

hs.urlevent.httpCallback = function(_, host, _, fullURL)
  host = host and host:lower()
  if GCLOUD_HOSTS[host] or isGcloudAuth(host, fullURL)
      or isWorkHost(host) or isWorkURL(fullURL) or isWorkSourceApp() then
    openInChrome(fullURL, cfg.work_chrome_profile)
  else
    openInChrome(fullURL, cfg.default_chrome_profile)
  end
end
hs.urlevent.setDefaultHandler("http")

return M
