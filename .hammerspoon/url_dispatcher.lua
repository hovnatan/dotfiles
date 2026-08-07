-- URL dispatcher: Hammerspoon is the default browser; Google Cloud links
-- open in a dedicated Chrome profile, everything else in the default one.
-- Only links from outside Chrome hit this.
--
-- Chrome profile directories map to accounts, so they live in the
-- gitignored local_config.lua:
--   return {
--     gcloud_chrome_profile = "...",  -- e.g. "Default", "Profile 1"
--     default_chrome_profile = "...",
--   }
-- Without it, links open in Chrome with no profile forcing.
local ok, cfg = pcall(require, "local_config")
if not ok then cfg = {} end

local GCLOUD_HOSTS = {
  ["console.cloud.google.com"] = true,
  ["console.developers.google.com"] = true,
  ["shell.cloud.google.com"] = true,
}

local function openInChrome(url, profile)
  if profile then
    hs.task.new("/usr/bin/open", nil, {
      "-na", "Google Chrome", "--args",
      "--profile-directory=" .. profile, url,
    }):start()
  else
    hs.urlevent.openURLWithBundle(url, "com.google.Chrome")
  end
end

hs.urlevent.httpCallback = function(_, host, _, fullURL)
  if host and GCLOUD_HOSTS[host] then
    openInChrome(fullURL, cfg.gcloud_chrome_profile)
  else
    openInChrome(fullURL, cfg.default_chrome_profile)
  end
end
hs.urlevent.setDefaultHandler("http")
