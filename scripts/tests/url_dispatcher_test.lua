-- url_dispatcher.lua and local_config.lua, the real modules, against
-- Hammerspoon doubles:
--
--   test --clicked URL (httpCallback)--> url_dispatcher --> chrome double
--   test --app activations (watcher)---^       |           records (profile, url)
--                                              v
--   test --link present? / module body--> local_config --> cfg, or alert + raise
--
-- Nothing opens: the chrome module is a double, so this runs in CI on Linux
-- and macOS without Chrome or Hammerspoon.
local repo = assert(arg[1], "pass the repo path")
package.path = repo .. "/home/.hammerspoon/?.lua;" .. package.path
local file = assert(io.open(assert(arg[2], "pass the event log path"), "a"))
file:setvbuf("line")
local scenario = "setup"
local function log(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [" .. scenario .. "] " .. string.format(fmt, ...)
  file:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end

local WORK, PERSONAL = "Work Profile", "Personal Profile"
local CFG = {
  work_chrome_profile = WORK,
  default_chrome_profile = PERSONAL,
  work_url_prefixes = { "https://github.com/someorg" },
}

-- What the modules did, for the asserts: Chrome launches and alerts.
local world

local function app(bundle)
  return {
    bundleID = function()
      return bundle
    end,
  }
end

local function stubHs(frontmost)
  return {
    configdir = "/stub/.hammerspoon",
    processInfo = { bundleID = "org.hammerspoon.Hammerspoon" },
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        log("alert: %s", msg)
      end,
    },
    fs = {
      -- Whether ~/.hammerspoon/local_hammerspoon.lua exists, as the test set it.
      symlinkAttributes = function(path)
        assert(path == "/stub/.hammerspoon/local_hammerspoon.lua", "unexpected path " .. path)
        return world.linkPresent and { mode = "link" } or nil
      end,
    },
    urlevent = {
      setDefaultHandler = function() end,
      openURLWithBundle = function(url)
        table.insert(world.opened, { profile = "(none)", url = url })
      end,
    },
    application = {
      frontmostApplication = function()
        return frontmost and app(frontmost)
      end,
      watcher = {
        activated = 5,
        new = function(fn)
          world.watch = fn
          return { start = function() end }
        end,
      },
    },
  }
end

local function stubLog()
  package.loaded.event_log = {
    new = function()
      return log, repo .. "/.logs/test"
    end,
  }
end

-- url_dispatcher with `cfg` as the machine's local config and `frontmost`
-- as the app in front at load time.
local function loadDispatcher(cfg, frontmost)
  world = { alerts = {}, opened = {} }
  stubLog()
  package.loaded.local_config = cfg
  package.loaded.chrome = {
    BUNDLE_ID = "com.google.Chrome",
    launchWithProfile = function(profile, url)
      table.insert(world.opened, { profile = profile, url = url })
    end,
  }
  _G.hs = stubHs(frontmost)
  return assert(loadfile(repo .. "/home/.hammerspoon/url_dispatcher.lua"))()
end

-- local_config with the link present or not and `body` as the module the
-- link points to (a function, as package.preload takes it; nil plays a
-- dangling link). The search path is emptied while it loads: on a Mac that
-- has the real link, home/.hammerspoon/local_hammerspoon.lua is in the
-- checkout and require would find it.
local function loadLocalConfig(linkPresent, body)
  world = { alerts = {}, opened = {}, linkPresent = linkPresent }
  stubLog()
  package.loaded.failure = nil
  require("failure")
  package.loaded.local_hammerspoon = nil
  package.preload.local_hammerspoon = body
  _G.hs = stubHs(nil)
  local chunk = assert(loadfile(repo .. "/home/.hammerspoon/local_config.lua"))
  local path, cpath = package.path, package.cpath
  package.path, package.cpath = "/nonexistent/?.lua", ""
  local ok, result = pcall(chunk)
  package.path, package.cpath = path, cpath
  if not ok then
    error(result, 0)
  end
  return result
end

local function click(url)
  local host = url:match("^https?://([^/:?#]+)")
  hs.urlevent.httpCallback("http", host, {}, url)
  return assert(world.opened[#world.opened], "click opened nothing").profile
end

local passed, failed = 0, 0
local function eq(got, want, what)
  assert(got == want, string.format("%s: got %s, want %s", what, tostring(got), tostring(want)))
end
local function raises(pattern, fn)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), "expected error: " .. pattern .. "; got " .. tostring(err))
end
local function test(name, fn)
  scenario = name
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    log("PASS")
  else
    failed = failed + 1
    log("FAIL: %s", err)
  end
end

-- Host -> profile, by URL alone (the source app plays no part here).
local HOSTS = {
  -- AWS is work-only: every AWS host, docs and S3 included.
  { "https://us-west-2.signin.aws.amazon.com/v1/authorize?client_id=x", WORK },
  { "https://us-west-2.console.aws.amazon.com/console/home", WORK },
  { "https://docs.aws.amazon.com/cli/", WORK },
  { "https://aws.amazon.com/", WORK },
  { "https://oidc.us-east-1.amazonaws.com/authorize?x", WORK },
  { "https://mybucket.s3.us-east-1.amazonaws.com/file", WORK },
  { "https://myorg.awsapps.com/start", WORK },
  { "https://ssoins-7223abcd.portal.us-east-1.app.aws/", WORK },
  { "https://us-east-1.signin.aws/platform/login", WORK },
  -- Slack, Google Cloud, the config's work prefixes.
  { "https://app.slack.com/client", WORK },
  { "https://console.cloud.google.com/home", WORK },
  { "https://accounts.google.com/o/oauth2/auth?scope=cloud-platform", WORK },
  { "https://github.com/someorg/repo", WORK },
  { "https://GitHub.com/SomeOrg/repo", WORK },
  -- Lookalikes and everything else stay personal.
  { "https://www.amazon.com/dp/123", PERSONAL },
  { "https://amazon.com/", PERSONAL },
  { "https://notaws.amazon.com/", PERSONAL },
  { "https://notamazonaws.com/", PERSONAL },
  { "https://example.aws.dev/", PERSONAL },
  { "https://notslack.com/", PERSONAL },
  { "https://accounts.google.com/o/oauth2/auth?scope=email", PERSONAL },
  { "https://github.com/otherorg/repo", PERSONAL },
}

test("isWorkLink: host and URL decide, case-insensitively", function()
  local d = loadDispatcher(CFG, "com.googlecode.iterm2")
  for _, c in ipairs(HOSTS) do
    local host = c[1]:match("^https?://([^/:?#]+)")
    eq(d.isWorkLink(host, c[1]) and WORK or PERSONAL, c[2], c[1])
    eq(d.isWorkLink(host:upper(), c[1]) and WORK or PERSONAL, c[2], c[1] .. " (upper-case host)")
  end
end)

test("isWorkLink: raises without the full URL", function()
  local d = loadDispatcher(CFG, nil)
  raises("pass the full URL", function()
    d.isWorkLink("example.com")
  end)
end)

test("isWorkLink: ignores which app is in front", function()
  local d = loadDispatcher(CFG, "com.tinyspeck.slackmacgap")
  eq(d.isWorkLink("example.com", "https://example.com/"), false, "personal link with Slack in front")
end)

test("click: routes by URL from a non-work app", function()
  loadDispatcher(CFG, "com.googlecode.iterm2")
  for _, c in ipairs(HOSTS) do
    eq(click(c[1]), c[2], c[1])
  end
end)

test("click: anything from Slack goes to work", function()
  loadDispatcher(CFG, "com.googlecode.iterm2")
  eq(click("https://example.com/"), PERSONAL, "before Slack")
  world.watch(nil, hs.application.watcher.activated, app("com.tinyspeck.slackmacgap"))
  eq(click("https://example.com/"), WORK, "Slack in front")
  -- Hammerspoon activating itself to deliver the URL does not count.
  world.watch(nil, hs.application.watcher.activated, app("org.hammerspoon.Hammerspoon"))
  eq(click("https://example.com/"), WORK, "Hammerspoon in front after Slack")
end)

test("click: Slack in front at load counts", function()
  loadDispatcher(CFG, "com.tinyspeck.slackmacgap")
  eq(click("https://example.com/"), WORK, "first click after reload")
end)

test("local_config: no link is an empty config", function()
  local cfg = loadLocalConfig(false, function()
    error("the module should not be required without the link")
  end)
  eq(next(cfg), nil, "config without the link")
  eq(#world.alerts, 0, "alerts")
end)

test("local_config: a working file is its table", function()
  local cfg = loadLocalConfig(true, function()
    return CFG
  end)
  eq(cfg.work_chrome_profile, WORK, "work profile")
end)

test("local_config: a broken file alerts and raises", function()
  raises("local_hammerspoon.lua", function()
    loadLocalConfig(true, function()
      error("syntax error near 'work_chrome_profile'")
    end)
  end)
  eq(#world.alerts, 1, "alerts")
  assert(world.alerts[1]:find("syntax error", 1, true), "alert names the error: " .. world.alerts[1])
end)

test("local_config: a dangling link alerts and raises", function()
  raises("local_hammerspoon.lua", function()
    loadLocalConfig(true, nil) -- link present, nothing to load behind it
  end)
  eq(#world.alerts, 1, "alerts")
end)

test("local_config: a file that returns no table alerts and raises", function()
  raises("not a table", function()
    loadLocalConfig(true, function()
      return true
    end)
  end)
  eq(#world.alerts, 1, "alerts")
end)

scenario = "summary"
log("%d passed, %d failed", passed, failed)
if failed > 0 then
  os.exit(1)
end
