-- iterm2_api.lua, the real module, against Hammerspoon doubles:
--
--   test --stdout chunks / exit--> module --> recorded banners, stdin, alerts
--   test --app watcher events----^
--
-- The script it runs (iterm2_api.py) is not started: the test plays its
-- side, events as JSON lines, cut into chunks anywhere. Timers fire only
-- when the test calls them. A stream callback that raises fails the test:
-- the real hs.task stops streaming after one does. Then the real clear_notifications.lua against
-- stub accessibility elements.
local repo = assert(arg[1], "pass the repo path")
-- The module's own requires that are not stubbed (failure.lua) load as is.
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

-- What the module did, for the asserts: banners (by title) up and
-- withdrawn, stdin writes, alerts, timers and tasks it made.
local world

local function stubHs()
  return {
    configdir = repo .. "/home/.hammerspoon",
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        log("alert: %s", msg)
      end,
    },
    -- JSON as the test registered it in `world.json`; anything else is
    -- broken JSON, which hs.json.decode raises on.
    json = {
      decode = function(s)
        return assert(world.json[s], "invalid JSON")
      end,
    },
    timer = {
      -- The test's clock: moved by hand (world.now).
      secondsSinceEpoch = function()
        return world.now
      end,
      doAfter = function(seconds, fn)
        local t = {
          seconds = seconds,
          fn = fn,
          stop = function(self)
            self.stopped = true
          end,
        }
        table.insert(world.timers, t)
        return t
      end,
    },
    image = {
      imageFromAppBundle = function(bundleID)
        return { icon = bundleID }
      end,
    },
    notify = {
      new = function(onClick, attrs)
        local n = { attrs = attrs, onClick = onClick }
        function n.send(self)
          world.up[self.attrs.title] = self
          return self
        end
        function n.withdraw(self)
          assert(world.up[self.attrs.title] == self, "withdrew a banner that is not up: " .. self.attrs.title)
          world.up[self.attrs.title] = nil
        end
        return n
      end,
      -- What is still up; a banner dismissed by hand (dismiss() below)
      -- leaves the list, as it does in Notification Center.
      deliveredNotifications = function()
        local list = {}
        for _, n in pairs(world.up) do
          table.insert(list, n)
        end
        return list
      end,
    },
    task = {
      new = function(path, onExit, onStream, args)
        local t = { path = path, onExit = onExit, onStream = onStream, args = args, input = {} }
        function t.start()
          return not world.startFails and t or nil
        end
        function t.pid()
          return 4242
        end
        function t.setInput(_, s)
          table.insert(t.input, s)
        end
        function t.terminate(self)
          self.terminated = true
        end
        table.insert(world.tasks, t)
        return t
      end,
    },
    application = {
      applicationsForBundleID = function()
        return world.itermAtLoad and { {} } or {}
      end,
      watcher = {
        launched = 1,
        terminated = 2,
        new = function(fn)
          world.watch = fn
          return { start = function() end }
        end,
      },
    },
  }
end

local function load(itermRunning)
  world = { alerts = {}, timers = {}, tasks = {}, up = {}, json = {}, itermAtLoad = itermRunning, now = 0 }
  package.loaded.failure = nil -- each case starts with no failure on record
  package.loaded.event_log = {
    new = function()
      return log, repo .. "/.logs/test"
    end,
  }
  _G.hs = stubHs()
  return assert(loadfile(repo .. "/home/.hammerspoon/iterm2_api.lua"))()
end

-- A JSON line the script would print, registered for the decode stub.
local function line(event)
  local s = "{" .. event.event .. ":" .. (event.session or "") .. "}"
  world.json[s] = event
  return s .. "\n"
end

local function bell(sid, name)
  return line({ event = "bell", session = sid, name = name, tab = 2, window = "win" })
end

-- The running task's stdout gets `text`, in chunks of `size` bytes.
local function say(text, size)
  local t = world.tasks[#world.tasks]
  size = size or #text
  for i = 1, #text, size do
    assert(t.onStream(t, text:sub(i, i + size - 1), "") == true, "stream callback stopped streaming")
  end
end

local function lastTimer()
  return world.timers[#world.timers]
end

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- iTerm2 launching or quitting, as the app watcher reports it.
local ITERM2 = {
  bundleID = function()
    return "com.googlecode.iterm2"
  end,
  pid = function()
    return 7
  end,
}
local function launched()
  world.watch(nil, 1, ITERM2)
end
local function quit()
  world.watch(nil, 2, ITERM2)
end

local passed, failed = 0, 0
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

test("starts the script with uv when iTerm2 runs at load, not otherwise", function()
  load(false)
  assert(#world.tasks == 0)
  load(true)
  local t = world.tasks[1]
  assert(t.path:match("/%.nix%-profile/bin/uv$"), t.path)
  assert(t.args[#t.args]:match("iterm2_api%.py$"))
end)

test("a bell puts up a banner, seen and gone withdraw it", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 3 }) .. bell("S1", "fish:~") .. bell("S2", "[bench]"))
  assert(world.timers[1].stopped, "ready did not stop the ready timeout")
  assert(world.up["fish:~ rang a bell"] and world.up["[bench] rang a bell"])
  assert(world.up["fish:~ rang a bell"].attrs.withdrawAfter == 0, "the banner would withdraw itself")
  local image = world.up["fish:~ rang a bell"].attrs.contentImage
  assert(image and image.icon == "com.googlecode.iterm2", "the banner has no iTerm2 icon")
  say(line({ event = "seen", session = "S1" }) .. line({ event = "gone", session = "S2" }))
  assert(next(world.up) == nil and next(m.banners) == nil)
end)

test("lines split across chunks are put together", function()
  load(true)
  say(bell("S1", "fish:~") .. bell("S2", "vim"), 3)
  assert(count(world.up) == 2)
end)

test("a click asks the script to bring that session to front", function()
  load(true)
  say(bell("S1", "fish:~"))
  world.up["fish:~ rang a bell"].onClick()
  assert(world.tasks[1].input[1] == "activate S1\n")
end)

test("a bad line alerts, and the lines after it are still handled", function()
  load(true)
  say("websockets.connect failed with InvalidMessage. Retrying.\n")
  assert(#world.alerts == 0, "a package message alerted")
  say(line({ event = "explode" }) .. "{not json\n" .. line({ event = "seen", session = "S9" }) .. bell("S1", "fish:~"))
  assert(#world.alerts == 3, "want 3 alerts, got " .. #world.alerts)
  assert(world.up["fish:~ rang a bell"], "the bell after the bad lines was lost")
end)

test("a bell while the banner is up adds none; once dismissed, a new one", function()
  load(true)
  say(bell("S1", "fish:~"))
  local first = world.up["fish:~ rang a bell"]
  say(bell("S1", "fish:~"))
  assert(world.up["fish:~ rang a bell"] == first, "a second banner for a session whose banner is up")

  -- alt+0 or its close button: gone from Notification Center, not withdrawn.
  world.up["fish:~ rang a bell"] = nil
  say(bell("S1", "fish:~"))
  local second = world.up["fish:~ rang a bell"]
  assert(second and second ~= first, "no new banner after the first was dismissed")
  say(line({ event = "seen", session = "S1" }))
  assert(next(world.up) == nil)
end)

test("iTerm2 quits: the script's end withdraws its banners, quietly", function()
  local m = load(true)
  say(bell("S1", "fish:~"))
  local t = world.tasks[1]
  t.onExit(1, "", "Traceback ... ConnectionClosed\n")
  assert(next(world.up) == nil and m.task == nil)
  world.watch(nil, 2, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
  })
  lastTimer().fn()
  assert(#world.alerts == 0, "an expected end alerted")

  -- The next launch starts it again.
  world.watch(nil, 1, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
    pid = function()
      return 7
    end,
  })
  assert(#world.tasks == 2 and m.task == world.tasks[2])
end)

test("the script ends while iTerm2 runs: raises after the grace period, and runs again", function()
  local m = load(true)
  world.tasks[1].onExit(1, "", "Traceback ... boom\n")
  raises("exited 1 while iTerm2 runs; started again", lastTimer().fn)
  assert(#world.tasks == 2 and m.task == world.tasks[2], "the script was not started again")
end)

test("a script that keeps ending is started again only so often", function()
  local m = load(true)
  for _ = 1, 3 do
    m.task.onExit(1, "", "")
    raises("started again", lastTimer().fn)
  end
  m.task.onExit(1, "", "")
  raises("not started again", lastTimer().fn)
  assert(#world.tasks == 4 and m.task == nil, "a fifth run, or a task left set")
end)

test("a script that never says ready is stopped and raises, once", function()
  local m = load(true)
  local timeout = world.timers[1]
  raises("not ready after", timeout.fn)
  assert(world.tasks[1].terminated and m.task == nil)
  local timers = #world.timers
  world.tasks[1].onExit(143, "", "")
  assert(#world.timers == timers and #world.alerts == 1, "its exit was judged as well")
end)

test("iTerm2 relaunching before the quit run has exited: the script starts", function()
  local m = load(true)
  say(bell("S1", "fish:~"))
  local old = world.tasks[1]
  quit()
  assert(old.terminated and next(world.up) == nil, "the quit left the run or its banners")
  launched()
  assert(#world.tasks == 2 and m.task == world.tasks[2], "the relaunch started no script")
  old.onExit(143, "", "")
  assert(m.task == world.tasks[2] and #world.alerts == 0, "the old run's exit counted")
end)

test("a bell whose banner failed: its seen and gone are quiet, the next bell shows", function()
  local m = load(true)
  say(line({ event = "bell", session = "S1", tab = 1, window = "" })) -- no name
  assert(#world.alerts == 1, "the bad bell did not alert")
  say(line({ event = "seen", session = "S1" }))
  assert(#world.alerts == 1 and m.banners.S1 == nil, "seen alerted again, or kept the entry")
  say(line({ event = "bell", session = "S1", tab = 1, window = "" }))
  say(line({ event = "gone", session = "S1" }))
  assert(#world.alerts == 2 and m.banners.S1 == nil, "gone alerted again, or kept the entry")
  say(bell("S1", "fish:~"))
  assert(world.up["fish:~ rang a bell"], "no banner after the failed ones")
end)

test("iTerm2 quitting stops a script still waiting to connect", function()
  load(true)
  world.watch(nil, 2, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
  })
  assert(world.tasks[1].terminated)
end)

test("a relaunch within the grace period is no failure of the last run", function()
  load(true)
  world.tasks[1].onExit(1, "", "Traceback ... ConnectionClosed\n")
  local grace = lastTimer()
  world.watch(nil, 1, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
    pid = function()
      return 7
    end,
  })
  assert(grace.stopped, "the exit check still runs after the relaunch")
end)

test("a failed start alerts without raising at load; the next launch retries", function()
  world = nil
  local m
  do
    -- load() with the start failing.
    local ok = pcall(function()
      world = { alerts = {}, timers = {}, tasks = {}, up = {}, json = {}, itermAtLoad = true, startFails = true }
      package.loaded.failure = nil
      package.loaded.event_log = {
        new = function()
          return log, repo .. "/.logs/test"
        end,
      }
      _G.hs = stubHs()
      m = assert(loadfile(repo .. "/home/.hammerspoon/iterm2_api.lua"))()
    end)
    assert(ok, "a failed start raised at load")
  end
  assert(#world.alerts == 1 and m.task == nil and #world.timers == 0, "state after a failed start")
  world.startFails = false
  world.watch(nil, 1, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
    pid = function()
      return 7
    end,
  })
  assert(m.task == world.tasks[2], "the next launch did not start the script")
end)

test("the exit of a replaced run is ignored", function()
  local m = load(true)
  local old = world.tasks[1]
  old.onExit(0, "", "")
  world.watch(nil, 1, {
    bundleID = function()
      return "com.googlecode.iterm2"
    end,
    pid = function()
      return 7
    end,
  })
  local timers = #world.timers
  old.onExit(0, "", "")
  assert(#world.timers == timers and m.task == world.tasks[2])
end)

-- The real clear_notifications.lua against stub accessibility elements. As
-- hs.axuielement does, a read that fails returns nil and a message, and an
-- attribute with no value (kAXErrorNoValue) a plain nil.
local NO_VALUE = {}

local function axElement(attrs)
  return {
    attributeValue = function(_, name)
      local value = attrs[name]
      if value == NO_VALUE then
        return nil
      end
      if value == nil then
        return nil, "Attribute is not supported by target"
      end
      return value
    end,
  }
end

local function realNotifications(windows)
  world = { alerts = {} }
  _G.hs = stubHs()
  hs.hotkey = {
    bind = function() end,
  }
  hs.application.applicationsForBundleID = function()
    return {
      {
        pid = function()
          return 2
        end,
      },
    }
  end
  hs.axuielement = {
    applicationElementForPID = function()
      return axElement({ AXTitle = "Notification Center", AXWindows = windows })
    end,
  }
  package.loaded.clear_notifications = nil
  return assert(loadfile(repo .. "/home/.hammerspoon/clear_notifications.lua"))()
end

test("an empty screen is no banner; a failed read at any level raises", function()
  assert(#realNotifications({}).banners() == 0)
  assert(#realNotifications({ axElement({ AXChildren = {} }) }).banners() == 0)
  assert(#realNotifications({ axElement({ AXChildren = NO_VALUE }) }).banners() == 0)
  assert(#realNotifications(NO_VALUE).banners() == 0)
  raises("window list could not be read", function()
    realNotifications(nil).banners()
  end)
  raises("child list could not be read", function()
    realNotifications({ axElement({}) }).banners()
  end)
end)

-- The switcher's two calls (iterm2_switcher.lua).
local function windowsLine(current)
  return line({ event = "windows", current = current, windows = {} })
end

test("listWindows asks a ready script and hands the reply to its caller", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }))
  local got
  m.listWindows(1, function(event)
    got = event.current
  end)
  assert(world.tasks[1].input[1] == "list\n", world.tasks[1].input[1])
  local limit = lastTimer()
  assert(limit.seconds == 1, limit.seconds)
  say(windowsLine("S1"))
  assert(got == "S1", tostring(got))
  assert(limit.stopped, "the reply did not stop its time limit")
  assert(#world.alerts == 0, world.alerts[1])
end)

test("one list at a time: a second while one is unanswered raises, after the reply it is asked", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }))
  m.listWindows(1, function() end)
  world.now = 0.4
  raises("has not answered the last window list, asked 0.4s ago", function()
    m.listWindows(1, function() end)
  end)
  assert(#world.tasks[1].input == 1, "the second list was sent")
  say(windowsLine("S1"))
  m.listWindows(1, function() end)
  assert(#world.tasks[1].input == 2, "the list after the reply was not sent")
end)

test("a list past its time alerts; its late reply is dropped, then the next is asked", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }))
  local called = false
  m.listWindows(1, function()
    called = true
  end)
  raises("did not list the windows within 1s", lastTimer().fn)
  raises("has not answered the last window list", function()
    m.listWindows(1, function() end)
  end)
  world.now = 3
  say(windowsLine("S1"))
  assert(not called, "a late reply reached its caller")
  assert(#world.alerts == 2, "the late reply alerted: " .. tostring(world.alerts[3]))
  m.listWindows(1, function() end)
  assert(#world.tasks[1].input == 2, "the list after the late reply was not sent")
end)

test("a caller's error is alerted once: not again if it alerted it, else as unexpected", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }))
  local callerFail = require("failure").new("iterm2_switcher", log)
  m.listWindows(1, function()
    callerFail("no screen at (700, 500)")
  end)
  say(windowsLine("S1"))
  assert(#world.alerts == 1 and world.alerts[1] == "iterm2_switcher: no screen at (700, 500)", world.alerts[1])

  m.listWindows(1, function()
    error("a bug in the switcher")
  end)
  say(line({ event = "windows", session = "2", current = "S1", windows = {} }))
  assert(#world.alerts == 2, "the unexpected error was not alerted once: " .. #world.alerts)
  assert(world.alerts[2]:find("iterm2_api: unexpected error: .*a bug in the switcher"), world.alerts[2])
  assert(not world.alerts[2]:find("windows", 1, true), "the alert holds the list's line: " .. world.alerts[2])
end)

test("activateWindow asks the script to bring that window to front", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }))
  m.activateWindow("pty-W1")
  assert(world.tasks[1].input[1] == "window pty-W1\n")
end)

test("with no script running, asking raises; before ready, a list raises, a click is sent", function()
  local idle = load(false)
  raises("iterm2_api.py is not running", function()
    idle.listWindows(1, function() end)
  end)
  raises("iterm2_api.py is not running", function()
    idle.activate("S1")
  end)
  local m = load(true)
  raises("still connecting", function()
    m.listWindows(1, function() end)
  end)
  m.activate("S1")
  assert(#world.tasks[1].input == 1 and world.tasks[1].input[1] == "activate S1\n", world.tasks[1].input[1])
end)

test("a window list nobody asked for alerts; a new run drops the list asked of the last", function()
  local m = load(true)
  say(line({ event = "ready", sessions = 1 }) .. windowsLine("S1"))
  assert(#world.alerts == 1 and world.alerts[1]:find("nobody asked for", 1, true), world.alerts[1])
  local called = false
  m.listWindows(1, function()
    called = true
  end)
  local limit = lastTimer()
  quit()
  assert(limit.stopped, "the quit run's list kept its time limit")
  launched()
  say(line({ event = "ready", sessions = 1 }) .. windowsLine("S1"))
  assert(not called, "the new run's reply went to the old run's caller")
  assert(#world.alerts == 2 and world.alerts[2]:find("nobody asked for", 1, true), world.alerts[2])
end)

scenario = "summary"
log("%d passed, %d failed", passed, failed)
file:close()
if failed > 0 then
  os.exit(1)
end
