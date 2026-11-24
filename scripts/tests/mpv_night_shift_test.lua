-- mpv_night_shift.lua against Hammerspoon doubles:
--
--   test --event(kind, bundle)--> watcher callback --> doubled hs.task
--   test --finish(code, out)----> the task's callback    (records the verb)
--   test --the timeout firing---> the doubled timer's function
--
-- night_shift.swift itself is not run: it needs macOS and switches the
-- screen's tint, so it is checked by hand on a Mac.
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

local MPV, CHROME = "io.mpv", "com.google.Chrome"

-- world.tasks: every task started, in order, each { verb, path, callback,
-- timer, terminated }. world.alerts and world.logged: what the module said.
-- world.startFails makes the next task's start() return false.
local world

local function app(bundle, pid)
  return {
    bundleID = function()
      return bundle
    end,
    pid = function()
      return pid
    end,
  }
end

local function stubHs()
  return {
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        note("alert: %s", msg)
      end,
    },
    task = {
      new = function(path, callback, args)
        local task = { path = path, callback = callback, verb = args[1], terminated = false }
        function task.start(self)
          if world.startFails then
            world.startFails = false
            return false
          end
          self.timer = world.lastTimer
          table.insert(world.tasks, self)
          return self
        end
        function task.terminate(self)
          self.terminated = true
        end
        return task
      end,
    },
    timer = {
      doAfter = function(seconds, fn)
        local timer = { seconds = seconds, fire = fn, stopped = false }
        function timer.stop(self)
          self.stopped = true
        end
        world.lastTimer = timer
        return timer
      end,
    },
    application = {
      applicationsForBundleID = function(bundle)
        assert(bundle == MPV, "asked for " .. tostring(bundle))
        local apps = {}
        for _, pid in ipairs(world.open) do
          table.insert(apps, app(MPV, pid))
        end
        return apps
      end,
      watcher = {
        launching = "launching",
        launched = "launched",
        activated = "activated",
        terminated = "terminated",
        new = function(fn)
          world.onApp = fn
          return { start = function() end }
        end,
      },
    },
  }
end

local function load(mpvOpen)
  world = { tasks = {}, alerts = {}, logged = {}, open = mpvOpen and { 1 } or {} }
  for _, name in ipairs({ "mpv_night_shift", "event_log", "failure" }) do
    package.loaded[name] = nil
  end
  package.preload.event_log = function()
    return {
      new = function()
        return function(fmt, ...)
          local line = string.format(fmt, ...)
          table.insert(world.logged, line)
          note("module: %s", line)
        end,
          "/logs/mpv_night_shift"
      end,
    }
  end
  _G.hs = stubHs()
  return require("mpv_night_shift")
end

-- An app event; world.open, the pids of the mpv processes running, follows
-- mpv's launches and quits. `listed` keeps a quit one in it, as a process
-- still listed when its quit is told would be.
local function event(kind, bundle, pid, listed)
  pid = pid or 1
  if bundle == MPV and kind == "launching" then
    table.insert(world.open, pid)
  elseif bundle == MPV and kind == "launched" then
    local listed = false
    for _, open in ipairs(world.open) do
      listed = listed or open == pid
    end
    if not listed then
      table.insert(world.open, pid)
    end
  elseif bundle == MPV and kind == "terminated" and not listed then
    for i, open in ipairs(world.open) do
      if open == pid then
        table.remove(world.open, i)
        break
      end
    end
  end
  world.onApp("the app's name", kind, bundle and app(bundle, pid))
end

-- The script of task `n` ending.
local function finish(n, code, out, err)
  world.tasks[n].callback(code, out or "", err or "")
end

local function verbs()
  local list = {}
  for _, task in ipairs(world.tasks) do
    table.insert(list, task.verb)
  end
  return table.concat(list, " ")
end

local function eq(got, want, what)
  assert(got == want, string.format("%s: got %s, want %s", what, tostring(got), tostring(want)))
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

test("mpv not open at load: nothing runs", function()
  load(false)
  eq(verbs(), "", "tasks")
end)

test("mpv open at load: off", function()
  load(true)
  eq(verbs(), "off", "tasks")
  eq(world.tasks[1].path, os.getenv("HOME") .. "/.dotfiles/scripts/macos/night_shift.swift", "script")
  finish(1, 0, "already off\n")
  eq(world.logged[1], "off (mpv open at load): already off", "log")
  assert(world.tasks[1].timer.stopped, "the timeout was left running")
end)

test("launch turns off, quit resumes", function()
  load(false)
  event("launched", MPV)
  eq(verbs(), "off", "after the launch")
  finish(1, 0, "was on: turned off\n")
  event("terminated", MPV)
  eq(verbs(), "off resume", "after the quit")
  finish(2, 0, "turned on (sunset to sunrise, and it is night)\n")
  eq(world.logged[2], "resume (mpv quit): turned on (sunset to sunrise, and it is night)", "log")
  eq(#world.alerts, 0, "alerts")
end)

test("other apps and other events of mpv run nothing", function()
  load(false)
  event("launched", CHROME)
  event("terminated", CHROME)
  event("activated", MPV)
  event("terminated", nil)
  eq(verbs(), "", "tasks")
end)

test("a launch from a terminal, told as launching alone, turns off", function()
  load(false)
  event("launching", MPV)
  eq(verbs(), "off", "after the launch")
  finish(1, 0, "was on: turned off\n")
  eq(world.logged[1], "off (mpv launching): was on: turned off", "log")
  event("terminated", MPV)
  eq(verbs(), "off resume", "after the quit")
end)

test("a launch told as launching and then launched asks for off twice", function()
  load(false)
  event("launching", MPV)
  finish(1, 0, "was on: turned off\n")
  event("launched", MPV)
  finish(2, 0, "already off\n")
  event("terminated", MPV)
  eq(verbs(), "off off resume", "tasks")
end)

test("a quit resumes only when no other mpv is left", function()
  load(false)
  event("launched", MPV, 1)
  finish(1, 0, "was on: turned off\n")
  event("launched", MPV, 2)
  finish(2, 0, "already off\n")
  event("terminated", MPV, 1)
  eq(verbs(), "off off", "after the first quit")
  eq(world.logged[3], "no resume (mpv quit): another mpv is open", "log")
  event("terminated", MPV, 2)
  eq(verbs(), "off off resume", "after the last quit")
end)

test("a quit one still listed does not count as another", function()
  load(false)
  event("launched", MPV, 1)
  finish(1, 0, "was on: turned off\n")
  event("terminated", MPV, 1, true)
  eq(verbs(), "off resume", "tasks")
end)

test("a quit while off still runs waits for it", function()
  load(false)
  event("launched", MPV)
  event("terminated", MPV)
  eq(verbs(), "off", "while off runs")
  finish(1, 0, "was on: turned off\n")
  eq(verbs(), "off resume", "once off ended")
end)

test("of several asked for while one runs, the last alone follows", function()
  load(false)
  event("launched", MPV)
  event("terminated", MPV)
  event("launched", MPV)
  event("terminated", MPV)
  finish(1, 0, "already off\n")
  eq(verbs(), "off resume", "tasks")
  finish(2, 0, "left off (no schedule)\n")
  eq(verbs(), "off resume", "nothing is left to run")
end)

test("a failed script alerts with its error, and the next event still runs", function()
  load(false)
  event("launched", MPV)
  finish(1, 1, "", "night_shift: CoreBrightness has no class CBBlueLightClient\n")
  eq(#world.alerts, 1, "alerts")
  assert(world.alerts[1]:find("no class CBBlueLightClient", 1, true), "the alert: " .. world.alerts[1])
  assert(world.alerts[1]:find("exit 1", 1, true), "the alert: " .. world.alerts[1])
  event("terminated", MPV)
  eq(verbs(), "off resume", "tasks")
end)

test("a script that hangs is killed and alerted, and its late end ignored", function()
  load(false)
  event("launched", MPV)
  world.tasks[1].timer.fire()
  assert(world.tasks[1].terminated, "the task was not terminated")
  eq(#world.alerts, 1, "alerts")
  assert(world.alerts[1]:find("took over", 1, true), "the alert: " .. world.alerts[1])
  event("terminated", MPV)
  eq(verbs(), "off resume", "the next event runs")
  finish(1, 15, "")
  eq(#world.alerts, 1, "alerts after the late end")
  eq(#world.logged, 1, "log lines after the late end")
end)

test("a script that cannot start alerts, and the next event still runs", function()
  load(false)
  world.startFails = true
  event("launched", MPV)
  eq(#world.alerts, 1, "alerts")
  assert(world.alerts[1]:find("could not start", 1, true), "the alert: " .. world.alerts[1])
  event("terminated", MPV)
  eq(verbs(), "resume", "tasks")
end)

scenario = "summary"
note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
