-- dock_cycle.lua, through the real alttab.lua, against Hammerspoon doubles:
--
--   test --hover()--> doubled Dock observer --> update --> doubled tap
--   test --click()--> doubled tap --> onLeftMouse --> doubled timer
--                                                        |
--                              doubled AltTab CLI <-- altTab.focus
local repo = assert(arg[1], "pass the repo path")
-- The module's own requires that are not stubbed (alttab.lua, failure.lua)
-- load as is.
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

local CHROME = "com.google.Chrome"
local DOWN, UP = 1, 2

-- What the module did, for the asserts.
local world

-- A Dock icon as accessibility gives it: of an app unless `subrole` says,
-- its top at `y`, else where the Dock being up puts it. The frames are this
-- Mac's, on its 1920 x 1080 screen (2026-11-18).
local UP, HIDDEN = 994, 1085
local function icon(path, x, y, subrole)
  return {
    AXSubrole = subrole or "AXApplicationDockItem",
    AXURL = path and { filePath = path },
    AXFrame = { x = x, y = y or UP, w = 65, h = 81 },
  }
end

local CHROME_PATH = "/Applications/Google Chrome.app"
local CHROME_ICON = icon(CHROME_PATH, 848)
local CHROME_ICON_HIDDEN = icon(CHROME_PATH, 848, HIDDEN)
local SLACK_ICON = icon("/Applications/Slack.app", 913)

-- Where the pointer is: on Chrome's icon, on Slack's, and in a window.
local ON_CHROME = { x = 880, y = 1040 }
local ON_SLACK = { x = 945, y = 1040 }
local IN_WINDOW = { x = 880, y = 500 }

local function app(bundle, path)
  return {
    bundleID = function()
      return bundle
    end,
    path = function()
      return path
    end,
    name = function()
      return bundle
    end,
  }
end

local function stubHs()
  -- The Dock's list of icons: what it has selected is read at each ask.
  local list = setmetatable({}, {
    __index = function(_, key)
      if key == "AXRole" then
        return "AXList"
      elseif key == "AXOrientation" then
        return world.orientation
      elseif key == "AXSelectedChildren" then
        return world.selected and { world.selected } or {}
      end
    end,
  })
  return {
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        note("alert: %s", msg)
      end,
    },
    axuielement = {
      applicationElement = function()
        return { AXChildren = world.noList and {} or { { AXRole = "AXMenuBar" }, list } }
      end,
      observer = {
        new = function(pid)
          local observer = { pid = pid, running = false, watched = {} }
          function observer.callback(self, fn)
            self.fn = fn
          end
          function observer.addWatcher(self, element, notification)
            assert(element == list, "watching something other than the Dock's list")
            self.watched[notification] = true
          end
          function observer.start(self)
            self.running = true
          end
          function observer.stop(self)
            self.running = false
          end
          table.insert(world.observers, observer)
          return observer
        end,
      },
    },
    eventtap = {
      event = { types = { leftMouseDown = DOWN, leftMouseUp = UP } },
      new = function(_, fn)
        local tap = { fn = fn, running = false }
        function tap.start(self)
          self.running = true
        end
        function tap.stop(self)
          self.running = false
        end
        world.tap = tap
        return tap
      end,
    },
    application = {
      applicationsForBundleID = function(bundle)
        assert(bundle == "com.apple.dock", "asked for " .. bundle)
        if not world.dockPid then
          return {}
        end
        local pid = world.dockPid
        return { {
          pid = function()
            return pid
          end,
        } }
      end,
      frontmostApplication = function()
        return world.front
      end,
      watcher = {
        activated = "activated",
        new = function(fn)
          world.onApp = fn
          return { start = function() end }
        end,
      },
    },
    mouse = {
      absolutePosition = function()
        return world.pointer
      end,
      getCurrentScreen = function()
        return {
          fullFrame = function()
            return { x = 0, y = 0, w = 1920, h = 1080 }
          end,
        }
      end,
    },
    timer = {
      doAfter = function(_, fn)
        table.insert(world.timers, fn)
        return {}
      end,
      secondsSinceEpoch = function()
        return world.now
      end,
    },
    -- AltTab's CLI: a command is noted, and answers as world says. Its reply
    -- stands for the JSON, so decode hands the table back.
    execute = function(command)
      table.insert(world.commands, command)
      local failing = command:find("--focus", 1, true) and world.focusError or world.listError
      if failing then
        return failing .. "\n", nil, "exit", 1
      end
      return "the list", true, "exit", 0
    end,
    json = {
      decode = function(text)
        if text ~= "the list" then
          error("not JSON")
        end
        return { windows = world.windows }
      end,
    },
  }
end

-- A window as AltTab lists it, of Chrome unless `bundle` says.
local function window(id, order, extra)
  local w = { id = id, lastFocusOrder = order, appBundleId = CHROME, isMinimized = false }
  for k, v in pairs(extra or {}) do
    w[k] = v
  end
  return w
end

-- Chrome in front with four windows, the pointer in a window, the Dock
-- having nothing selected.
local function load(setup)
  world = {
    alerts = {},
    logged = {},
    commands = {},
    timers = {},
    observers = {},
    dockPid = 77,
    orientation = "AXHorizontalOrientation",
    front = app(CHROME, CHROME_PATH),
    pointer = IN_WINDOW,
    now = 1000,
    windows = { window(101, 0), window(102, 1), window(103, 4), window(104, 6) },
  }
  for k, v in pairs(setup or {}) do
    world[k] = v
  end
  for _, name in ipairs({ "dock_cycle", "alttab", "failure", "event_log" }) do
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
          "/logs/dock_cycle"
      end,
    }
  end
  _G.hs = stubHs()
  return require("dock_cycle")
end

-- The Dock selects `selected` with the pointer at `pointer`, and says so to
-- the observer of the Dock running now, if that asked to be told.
local function hover(selected, pointer)
  world.selected, world.pointer = selected, pointer
  local observer = world.observers[#world.observers]
  if observer.running and observer.watched.AXSelectedChildrenChanged then
    observer.fn()
  end
end

-- Loaded, the pointer on Chrome's icon.
local function onChrome(setup)
  load(setup)
  hover(CHROME_ICON, ON_CHROME)
end

local function mouse(kind, flags)
  return {
    getType = function()
      return kind
    end,
    getFlags = function()
      return flags or {}
    end,
    location = function()
      return world.pointer
    end,
  }
end

-- Press and release, then run what was left for after the tap: what each of
-- the two returned, true meaning the event went no further.
local function click(flags)
  assert(world.tap.running, "a click with the tap stopped")
  local down = world.tap.fn(mouse(DOWN, flags))
  local up = world.tap.fn(mouse(UP, flags))
  for _, fn in ipairs(world.timers) do
    fn()
  end
  world.timers = {}
  return down, up
end

-- A click the module leaves to whatever is under the pointer.
local function clickLeftAlone(what, flags)
  local down, up = click(flags)
  assert(down == false and up == false, what .. " was taken")
end

-- The ids brought forward so far.
local function focused()
  local ids = {}
  for _, command in ipairs(world.commands) do
    table.insert(ids, command:match("%-%-focus=(%d+) "))
  end
  return table.concat(ids, " ")
end

-- AltTab's order once 102 has come forward from 101.
local function after102()
  return { window(102, 0), window(101, 1), window(103, 4), window(104, 6) }
end

local function loggedLine(text)
  for _, line in ipairs(world.logged) do
    if line:find(text, 1, true) then
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

test("the tap runs only while the pointer is on the front app's icon", function()
  load()
  assert(world.observers[1].running and world.observers[1].pid == 77, "the Dock is not watched")
  assert(not world.tap.running, "the tap runs with the pointer in a window")
  hover(SLACK_ICON, ON_SLACK)
  assert(not world.tap.running, "the tap runs on another app's icon")
  hover(CHROME_ICON, ON_CHROME)
  assert(world.tap.running, "the tap did not start on the front app's icon")
  hover(SLACK_ICON, ON_SLACK)
  assert(not world.tap.running, "the tap did not stop on the next icon")
end)

-- The Dock names the icon again as the pointer leaves it, e.g. pointer
-- (867, 981) over the frame from y 994 (2026-11-18).
test("the pointer leaving the Dock stops the tap, though the Dock names the icon still", function()
  onChrome()
  hover(CHROME_ICON, { x = 867, y = 981 })
  assert(not world.tap.running, "the tap still runs")
end)

-- The notification comes as the pointer crosses the icon's side, e.g.
-- pointer x 1010 for the frame from x 1010, read a point short of it.
test("the pointer read a point short of the icon's side arms the tap", function()
  load()
  hover(CHROME_ICON, { x = 847.4, y = 1040 })
  assert(world.tap.running, "the tap did not start")
end)

-- Pointer at the screen's bottom edge (867, 1080), the icon's frame not up
-- yet at y 1085, and no second notification once it is (2026-11-18).
test("an icon named while the Dock slides in arms the tap", function()
  load()
  hover(CHROME_ICON_HIDDEN, { x = 867, y = 1080 })
  assert(world.tap.running, "the tap did not start")
end)

test("a folder or the Trash under the pointer is not an app's icon", function()
  load()
  hover(icon(CHROME_PATH, 848, UP, "AXFolderDockItem"), ON_CHROME)
  assert(not world.tap.running, "the tap runs on a folder")
  hover(icon(nil, 848, UP, "AXTrashDockItem"), ON_CHROME)
  assert(not world.tap.running, "the tap runs on the Trash")
end)

test("another app coming to front under the pointer stops the tap", function()
  onChrome()
  world.front = app("com.tinyspeck.slackmacgap", "/Applications/Slack.app")
  world.onApp("Slack", "activated")
  assert(not world.tap.running, "the tap still runs for the app left")
end)

test("a Dock on a side of the screen is said, not guessed at", function()
  onChrome({ orientation = "AXVerticalOrientation" })
  assert(not world.tap.running, "the tap runs")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(world.alerts[1]:find("only one at the bottom is handled", 1, true), world.alerts[1])
end)

test("clicks walk the windows, the most recently used first, and go round", function()
  onChrome({ windows = { window(103, 4), window(101, 0), window(104, 6), window(102, 1) } })
  for _ = 1, 5 do
    local down, up = click()
    assert(down == true and up == true, "a click reached the Dock")
  end
  assert(focused() == "102 103 104 101 102", focused())
end)

-- Each window landed on becomes AltTab's most recent, so asking at every
-- click would flip between the first two.
test("the order is the one at the walk's first click", function()
  onChrome()
  click()
  world.windows = after102()
  click()
  assert(focused() == "102 103", focused())
end)

test("a walk left alone starts over from the order then", function()
  onChrome()
  click()
  world.windows = after102()
  world.now = world.now + 6
  click()
  assert(focused() == "102 101", focused())
end)

test("the pointer leaving the icon ends the walk", function()
  onChrome()
  click()
  world.windows = after102()
  hover(CHROME_ICON, IN_WINDOW)
  hover(CHROME_ICON, ON_CHROME)
  click()
  assert(focused() == "102 101", focused())
end)

-- A click then is for the window under the pointer; the walk goes on once
-- the Dock is back.
test("the Dock hiding under a pointer that stays put does not end the walk", function()
  onChrome()
  click()
  hover(CHROME_ICON_HIDDEN, ON_CHROME)
  clickLeftAlone("a click with the Dock hidden")
  assert(not world.tap.running, "the tap still runs")
  hover(CHROME_ICON, ON_CHROME)
  click()
  assert(focused() == "102 103", focused())
end)

-- The Dock tells nothing of a pointer that leaves while it is hidden, or
-- past the end of its row.
test("a click off the icon is left alone, and stops the tap", function()
  for what, pointer in pairs({ ["in a window"] = IN_WINDOW, ["beside the icon"] = { x = 700, y = 1040 } }) do
    onChrome()
    world.pointer = pointer
    clickLeftAlone("a click " .. what)
    assert(not world.tap.running, "the tap still runs after a click " .. what)
    assert(focused() == "", "a window came forward")

    -- Where the pointer and the icon were, to tell a click that left the
    -- Dock from one misjudged.
    local line =
      string.format("disarmed: click off the icon: pointer (%d, %d), icon (848, 994) 65 x 81", pointer.x, pointer.y)
    assert(loggedLine(line), "not logged: " .. line)
  end
end)

test("a click on an icon whose app has quit says the icon is gone", function()
  local quit = icon(CHROME_PATH, 848)
  load()
  hover(quit, ON_CHROME)
  quit.AXFrame = nil
  clickLeftAlone("a click on a gone icon")
  assert(loggedLine("disarmed: click off the icon: pointer (880, 1040), icon gone"), "not logged")
end)

test("a click below the icon, down to the screen's edge, is on it", function()
  onChrome()
  world.pointer = { x = 880, y = 1079.5 }
  local down = click()
  assert(down == true, "the click reached the Dock")
end)

test("a click with a modifier held is the Dock's", function()
  onChrome()
  clickLeftAlone("a modified click", { ctrl = true })
  assert(#world.commands == 0, "AltTab was asked")
end)

test("an app with one window keeps the Dock's own click", function()
  onChrome({ windows = { window(101, 0), window(201, 1, { appBundleId = "com.tinyspeck.slackmacgap" }) } })
  clickLeftAlone("the click")
  assert(focused() == "", "a window came forward")
  assert(#world.alerts == 0, "alerted: " .. tostring(world.alerts[1]))
end)

test("a minimized window is not walked to", function()
  onChrome({ windows = { window(101, 0), window(102, 1, { isMinimized = true }), window(103, 2) } })
  click()
  click()
  assert(focused() == "103 101", focused())
end)

test("what AltTab says goes in the alert, and the click is the Dock's", function()
  onChrome({ listError = "AltTab.app needs to be running for CLI commands to work" })
  clickLeftAlone("a click with no list")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(
    world.alerts[1]:find("dock_cycle: listing windows failed (exit 1): AltTab.app needs to be running", 1, true),
    world.alerts[1]
  )
end)

test("a window that cannot come forward is alerted, and the next click starts over", function()
  onChrome()
  world.focusError = "Couldn't execute command. Is it correct?"
  click()
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(world.alerts[1]:find("bringing window 102 forward failed", 1, true), world.alerts[1])
  world.focusError = nil
  world.windows = { window(101, 0), window(103, 4), window(104, 6) }
  click()
  assert(focused() == "102 103", focused())
end)

test("a restarted Dock is watched from the next app switch", function()
  load()
  world.dockPid = nil
  world.onApp("Chrome", "activated")
  assert(#world.observers == 1 and #world.alerts == 0, "the moment with no Dock was not waited out")
  world.dockPid = 78
  world.onApp("Chrome", "activated")
  assert(#world.observers == 2, "the new Dock is not watched")
  assert(not world.observers[1].running, "the old Dock's observer still runs")
  assert(world.observers[2].pid == 78, "watching pid " .. world.observers[2].pid)
  hover(CHROME_ICON, ON_CHROME)
  assert(world.tap.running, "the new Dock's hover did not arm the tap")
end)

test("a Dock with no list of icons is said at load", function()
  local ok, err = pcall(load, { noList = true })
  assert(not ok, "it loaded")
  assert(tostring(err):find("shows no list of icons", 1, true), tostring(err))
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
end)

test("no Dock at load is said", function()
  local ok, err = pcall(load, { dockPid = false })
  assert(not ok, "it loaded")
  assert(tostring(err):find("the Dock is not running", 1, true), tostring(err))
end)

test("arming and clicks are logged", function()
  onChrome()
  click()
  hover(CHROME_ICON, IN_WINDOW)
  for _, text in ipairs({
    "watching the Dock (pid 77)",
    "armed: pointer on com.google.Chrome's icon",
    "walk: 4 windows of com.google.Chrome",
    "click: window 2 of 4, id 102",
    "disarmed: pointer off the icon",
    "walk over: pointer left the icon",
  }) do
    assert(loggedLine(text), "not logged: " .. text)
  end
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
