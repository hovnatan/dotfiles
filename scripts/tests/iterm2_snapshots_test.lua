-- iterm2_snapshots.lua, the real module, against Hammerspoon doubles:
--
--   test --tick()--> doubled hs.timer --> M.snapshot --> doubled hs.task
--                         |                  |
--                         | callback raised  v
--                         v               alerts, event log (world)
--                    stopped for good
--
-- The doubled repeating timer behaves as the real one does: hs.timer.doEvery
-- has no continueOnError, so a callback that raises once stops it for good,
-- with the error in the Console alone (measured 2026-11-04: fired once, then
-- running() was false). Snapshots stopped silently that way on 2026-11-02.
local repo = assert(arg[1], "pass the repo path")
-- The module's own requires that are not stubbed (failure.lua) load as is.
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

-- What the module did, for the asserts.
local world

local function stubHs()
  return {
    configdir = repo .. "/home/.hammerspoon",
    fs = {
      pathToAbsolute = function(path)
        return path
      end,
    },
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        note("alert: %s", msg)
      end,
    },
    timer = {
      doEvery = function(seconds, fn)
        local t = { seconds = seconds, fn = fn, running = true }
        world.repeating = t
        return t
      end,
      doAfter = function(_, fn)
        return { fn = fn, stop = function() end }
      end,
    },
    task = {
      new = function(path, onExit, args)
        if world.taskError then
          error(world.taskError)
        end
        local t = { path = path, onExit = onExit, args = args }
        function t.environment()
          return { PATH = "/usr/bin" }
        end
        function t.setEnvironment() end
        function t.start()
          return t
        end
        function t.pid()
          return 4242
        end
        table.insert(world.tasks, t)
        return t
      end,
    },
  }
end

-- One firing of the repeating timer, as the real one treats its callback.
local function tick()
  local t = assert(world.repeating, "the module made no repeating timer")
  assert(t.running, "a tick on a stopped timer: nothing would fire")
  local ok, err = pcall(t.fn)
  if not ok then
    t.running = false
    note("timer stopped by its callback's error: %s", tostring(err))
  end
end

local function load()
  world = { alerts = {}, tasks = {}, logged = {} }
  package.loaded.iterm2_snapshots = nil
  package.loaded.failure = nil
  package.preload.iterm2_api = function()
    return { itermRunning = true }
  end
  package.preload.event_log = function()
    return {
      new = function()
        return function(fmt, ...)
          local line = string.format(fmt, ...)
          table.insert(world.logged, line)
          note("module: %s", line)
        end,
          "/logs/iterm2_snapshots"
      end,
    }
  end
  package.loaded.iterm2_api = nil
  package.loaded.event_log = nil
  _G.hs = stubHs()
  return require("iterm2_snapshots")
end

local function logged(pattern)
  for _, line in ipairs(world.logged) do
    if line:find(pattern, 1, true) then
      return true
    end
  end
  return false
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

test("a tick starts a snapshot", function()
  load()
  tick()
  assert(#world.tasks == 1, "no snapshot task started")
  assert(world.tasks[1].args[2] == "snapshot", "the task is not the snapshot command")
end)

-- The 2026-11-02 failure: one raising tick must cost that snapshot only.
test("an error in a tick leaves the timer running, and the next tick snapshots", function()
  load()
  world.taskError = "boom in hs.task.new"
  tick()
  assert(world.repeating.running, "the error stopped the timer: no snapshot would ever run again")
  world.taskError = nil
  tick()
  assert(#world.tasks == 1, "the tick after the error started no snapshot")
end)

test("an error in a tick is alerted and in the event log, naming the error", function()
  load()
  world.taskError = "boom in hs.task.new"
  tick()
  assert(#world.alerts == 1, "expected one alert, got " .. #world.alerts)
  assert(world.alerts[1]:find("boom in hs.task.new", 1, true), "the alert does not name the error")
  assert(logged("boom in hs.task.new"), "the event log does not name the error")
end)

os.exit(failures == 0 and 0 or 1)
