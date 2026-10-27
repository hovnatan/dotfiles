-- URL dispatcher: Hammerspoon is the default browser; Google Cloud links,
-- AWS console and login (CLI sign-in, SSO), work URLs, Slack's own domains
-- and anything clicked in a work app (Slack) open in the work Chrome
-- profile, everything else in the default one. Only links from outside
-- Chrome hit this.
--
--   click --> httpCallback --> isWorkLink(host, url) --or--> source app is
--                                 GCLOUD_HOSTS / auth       a work app (Slack)
--                                 WORK_HOST_SUFFIXES             |
--                                 work_url_prefixes              v
--                              work profile if either, else the default one
--
-- Chrome profile directories map to accounts and work URLs name the
-- employer, so both live outside the repo, in the machine-private config
-- (local_config.lua says how it loads):
--   return {
--     work_chrome_profile = "...",  -- e.g. "Default", "Profile 1"
--     default_chrome_profile = "...",
--     work_url_prefixes = { "https://github.com/someorg" },  -- optional
--   }
-- Without it, links open in Chrome with no profile forcing.
local chrome = require("chrome")
local cfg = require("local_config")
local M = {}

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

-- Hosts that are work whatever the source app, matched as a suffix so the
-- host itself and every subdomain count. Not employer-identifying, so
-- unlike work_url_prefixes these can live in the repo. AWS is work-only, so
-- all of it goes to the work profile, docs and S3 links included:
--   slack.com       app.slack.com, <workspace>.slack.com
--   aws.amazon.com  us-west-2.signin.aws.amazon.com (`aws login`), console
--   amazonaws.com   oidc.us-east-1.amazonaws.com (`aws sso login`), S3
--   awsapps.com     SSO start page <id>.awsapps.com/start
--   aws             AWS's own top-level domain: us-east-1.signin.aws
--                   (Identity Center sign-in), <id>.portal.us-east-1.app.aws
-- amazon.com itself (shopping) does not match: only "aws.amazon.com" and
-- names ending in ".aws.amazon.com" do.
local WORK_HOST_SUFFIXES = {
  "slack.com",
  "aws.amazon.com",
  "amazonaws.com",
  "awsapps.com",
  "aws",
}

local function isWorkHost(host)
  if not host then
    return false
  end
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
  if bundle and bundle ~= hs.processInfo.bundleID then
    sourceApp = bundle
  end
end

rememberSource(hs.application.frontmostApplication())

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated then
    rememberSource(app)
  end
end)
M.watcher:start()

local function isWorkSourceApp()
  return WORK_SOURCE_BUNDLES[sourceApp] ~= nil
end

local function isWorkURL(url)
  local lower = url:lower()
  for _, prefix in ipairs(cfg.work_url_prefixes or {}) do
    if lower:sub(1, #prefix) == prefix:lower() then
      return true
    end
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

-- Whether the link itself is work, from its host and URL alone. The source
-- app is left out on purpose, so this answers the same from a terminal as
-- from a click and can be checked without opening a tab:
--   hs -c 'return require("url_dispatcher").isWorkLink("oidc.us-east-1.amazonaws.com", "https://oidc.us-east-1.amazonaws.com/")'
function M.isWorkLink(host, fullURL)
  assert(type(fullURL) == "string", "isWorkLink: pass the full URL as well as the host")
  host = host and host:lower()
  return (GCLOUD_HOSTS[host] or isGcloudAuth(host, fullURL) or isWorkHost(host) or isWorkURL(fullURL)) and true or false
end

hs.urlevent.httpCallback = function(_, host, _, fullURL)
  if M.isWorkLink(host, fullURL) or isWorkSourceApp() then
    openInChrome(fullURL, cfg.work_chrome_profile)
  else
    openInChrome(fullURL, cfg.default_chrome_profile)
  end
end
hs.urlevent.setDefaultHandler("http")

return M
