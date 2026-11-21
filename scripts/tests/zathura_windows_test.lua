-- zathura_windows.lua's app watcher, against Hammerspoon doubles:
--
--   test --event(kind, bundle)--> watcher callback --> doubled tap
--                                        |
--                    doubled frontmostApplication: counts each ask
--
-- The key handling (pgrep, AXFrontmost, activate) is not driven here.
local repo = assert(arg[1], "pass the repo path")
package.path = repo .. "/home/.hammerspoon/?.lua;" .. package.path
local file = assert(io.open(assert(arg[2], "pass the event log path"), "a"))
file:setvbuf("line")
local scenario = "setup"
local function note(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [" .. scenario .. "] " .. string.format(fmt, ...)
  file:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end

local VIEWER, CHROME = "com.hovnatan.zathura.viewer", "com.google.Chrome"

-- world.front is the frontmost app's bundle, or nil for none: the lock
-- screen. world.asked counts the asks for it.
local world

local function app(bundle)
  return {
    bundleID = function()
      return bundle
    end,
  }
end

local function stubHs()
  return {
    keycodes = { map = { ["`"] = 50 } },
    eventtap = {
      event = { types = { keyDown = 10 }, properties = { keyboardEventAutorepeat = "autorepeat" } },
      new = function()
        local tap = { running = false }
        function tap.start(self)
          self.running = true
        end
        function tap.stop(self)
          self.running = false
        end
        function tap.isEnabled(self)
          return self.running
        end
        world.tap = tap
        return tap
      end,
    },
    application = {
      frontmostApplication = function()
        world.asked = world.asked + 1
        return world.front and app(world.front)
      end,
      watcher = {
        launched = "launched",
        activated = "activated",
        deactivated = "deactivated",
        terminated = "terminated",
        new = function(fn)
          world.onApp = fn
          return { start = function() end }
        end,
      },
    },
  }
end

-- Load the module with `front` frontmost; the asks at load are not counted.
local function load(front)
  world = { front = front, asked = 0 }
  for _, name in ipairs({ "zathura_windows", "event_log" }) do
    package.loaded[name] = nil
  end
  package.preload.event_log = function()
    return {
      new = function()
        return function(fmt, ...)
          note("module: %s", string.format(fmt, ...))
        end,
          "/logs/zathura_windows"
      end,
    }
  end
  _G.hs = stubHs()
  require("zathura_windows")
  world.asked = 0
end

-- An app event as the watcher gets it, with `front` frontmost by then.
local function event(kind, bundle, front)
  world.front = front
  world.onApp("the app's name", kind, app(bundle))
end

local failures = 0
local function test(name, fn)
  scenario = name
  local ok, err = pcall(fn)
  if ok then
    note("PASS")
  else
    failures = failures + 1
    note("FAIL: %s", tostring(err))
  end
end

test("at load the tap runs if a viewer is frontmost, and not otherwise", function()
  load(VIEWER)
  assert(world.tap.running, "stopped with a viewer frontmost")
  load(CHROME)
  assert(not world.tap.running, "running with Chrome frontmost")
  load(nil)
  assert(not world.tap.running, "running with nothing frontmost")
end)

test("a viewer coming to the front starts the tap, another app stops it", function()
  load(CHROME)
  event("deactivated", CHROME, VIEWER)
  event("activated", VIEWER, VIEWER)
  assert(world.tap.running, "stopped after a viewer was activated")
  event("deactivated", VIEWER, CHROME)
  event("activated", CHROME, CHROME)
  assert(not world.tap.running, "running after Chrome was activated")
end)

-- 2026-11-21: one "LuaSkin: Unable to fetch frontmost application" at each
-- lock and each unlock, about 12 a day, from the ask a leaving app led to.
test("a lock and an unlock with no viewer in front ask for no frontmost app", function()
  load(CHROME)
  event("deactivated", CHROME, nil)
  event("deactivated", "com.apple.loginwindow", nil)
  event("activated", CHROME, nil)
  assert(world.asked == 0, "asked for the frontmost app " .. world.asked .. " time(s)")
  assert(not world.tap.running, "the tap runs")
end)

test("an app coming to the front is taken from the event, with no ask", function()
  load(CHROME)
  event("activated", VIEWER, nil)
  assert(world.asked == 0, "asked for the frontmost app")
  assert(world.tap.running, "stopped though a viewer was activated")
end)

-- macOS says a viewer has ended after it says the next app is in front.
test("a viewer that ends leaves the tap to what is frontmost then", function()
  load(VIEWER)
  event("activated", VIEWER, VIEWER)
  event("terminated", VIEWER, VIEWER)
  assert(world.tap.running, "stopped though another viewer is frontmost")
  event("terminated", VIEWER, CHROME)
  assert(not world.tap.running, "running though Chrome is frontmost")
end)

test("the last viewer ending with nothing left in front stops the tap", function()
  load(VIEWER)
  event("terminated", VIEWER, nil)
  assert(not world.tap.running, "running with no app frontmost")
end)

test("an app that only launches or ends elsewhere changes nothing", function()
  load(VIEWER)
  event("launched", CHROME, VIEWER)
  event("terminated", CHROME, VIEWER)
  assert(world.tap.running, "stopped by an app that was never in front")
  load(CHROME)
  event("launched", VIEWER, CHROME)
  assert(not world.tap.running, "started by a viewer that has not come to the front")
  assert(world.asked == 0, "asked for the frontmost app")
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
