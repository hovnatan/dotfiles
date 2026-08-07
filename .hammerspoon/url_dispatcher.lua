-- URL dispatcher: Hammerspoon is the default browser; Google Cloud links and
-- work URLs open in the work Chrome profile, everything else in the default
-- one. Only links from outside Chrome hit this.
--
-- Chrome profile directories map to accounts and work URLs name the
-- employer, so both live in the gitignored local_config.lua:
--   return {
--     work_chrome_profile = "...",  -- e.g. "Default", "Profile 1"
--     default_chrome_profile = "...",
--     work_url_prefixes = { "https://github.com/someorg" },  -- optional
--   }
-- Without it, links open in Chrome with no profile forcing.
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

local function isWorkURL(url)
  local lower = url:lower()
  for _, prefix in ipairs(cfg.work_url_prefixes or {}) do
    if lower:sub(1, #prefix) == prefix:lower() then return true end
  end
  return false
end

local function openInChrome(url, profile)
  if profile then
    -- open -n hands the URL to the running Chrome via a short-lived second
    -- instance, so macOS never activates Chrome itself; raise it once the
    -- handoff is done (Chrome has already raised the profile's window
    -- within its own window stack by then).
    hs.task.new("/usr/bin/open", function()
      hs.timer.doAfter(0.2, function()
        local chrome = hs.application.applicationsForBundleID("com.google.Chrome")[1]
        if chrome then chrome:activate() end
      end)
    end, {
      "-na", "Google Chrome", "--args",
      "--profile-directory=" .. profile, url,
    }):start()
  else
    hs.urlevent.openURLWithBundle(url, "com.google.Chrome")
  end
end

hs.urlevent.httpCallback = function(_, host, _, fullURL)
  host = host and host:lower()
  if (host and (GCLOUD_HOSTS[host] or isGcloudAuth(host, fullURL))) or isWorkURL(fullURL) then
    openInChrome(fullURL, cfg.work_chrome_profile)
  else
    openInChrome(fullURL, cfg.default_chrome_profile)
  end
end
hs.urlevent.setDefaultHandler("http")
