-- switcher.lua, through the real iterm2_switcher.lua and ghostty_switcher.lua,
-- against Hammerspoon doubles:
--
--   test --click()--> doubled tap --> onOtherMouse --> doubled timer
--                                                        |
--                       doubled picker <-- rows <-- opts.list
--                            |
--   test --pick()------------+--> opts.activate --> doubled AppleScript / api
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

local GHOSTTY, ITERM2 = "com.mitchellh.ghostty", "com.googlecode.iterm2"
local APP_PID, OTHER_PID = 500, 900
local DOWN, DRAGGED, UP = 1, 2, 3

-- What the module did, for the asserts.
local world

local focusable

local function app(bundle)
  return {
    bundleID = function()
      return bundle
    end,
    pid = function()
      return bundle == "other" and OTHER_PID or APP_PID
    end,
  }
end

-- Ghostty as hs.application.get gives it: one watcher at a time, for the asserts.
function focusable()
  local a = app(GHOSTTY)
  function a.newWatcher(_, fn)
    local w = { fn = fn, running = false }
    function w.start(self, events)
      assert(events[1] == "AXFocusedWindowChanged", "watching something else")
      self.running = true
    end
    function w.stop(self)
      self.running = false
    end
    world.focus = w
    table.insert(world.focusWatchers, w)
    return w
  end
  return a
end

local function stubHs()
  local element = {}
  function element.pid()
    return world.underPointer
  end
  local system = {}
  function system.setTimeout() end
  function system.elementAtPosition()
    return element
  end
  return {
    inspect = function(v)
      return type(v) == "table" and (v.NSAppleScriptErrorMessage or "?") or tostring(v)
    end,
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        note("alert: %s", msg)
      end,
    },
    axuielement = {
      systemWideElement = function()
        return system
      end,
    },
    eventtap = {
      event = {
        types = { otherMouseDown = DOWN, otherMouseDragged = DRAGGED, otherMouseUp = UP },
        properties = { mouseEventButtonNumber = "button" },
      },
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
      frontmostApplication = function()
        return app(world.front)
      end,
      get = function(bundle)
        assert(bundle == GHOSTTY, "asked for " .. bundle)
        return world.ghosttyRuns and focusable() or nil
      end,
      watcher = {
        activated = "activated",
        terminated = "terminated",
        new = function(fn)
          table.insert(world.onApps, fn)
          return { start = function() end }
        end,
      },
    },
    uielement = { watcher = { focusedWindowChanged = "AXFocusedWindowChanged" } },
    timer = {
      doAfter = function(_, fn)
        table.insert(world.timers, fn)
        return {}
      end,
      delayed = {
        new = function(seconds, fn)
          local t = { seconds = seconds, fn = fn, pending = false }
          function t.start(self)
            self.pending = true
          end
          function t.stop(self)
            self.pending = false
          end
          world.settle = t
          return t
        end,
      },
    },
    osascript = {
      applescript = function(script)
        table.insert(world.scripts, script)
        if world.scriptError then
          return false, nil, { NSAppleScriptErrorMessage = world.scriptError }
        end
        if script:find("id of first window", 1, true) then
          return true, world.windows[1] and world.windows[1][1] or ""
        end
        return true, world.windows
      end,
    },
  }
end

local function load(module, setup)
  world = {
    alerts = {},
    logged = {},
    shown = {},
    scripts = {},
    timers = {},
    activated = {},
    onApps = {},
    focusWatchers = {},
    ghosttyRuns = module == "ghostty_switcher",
    underPointer = APP_PID,
    front = module == "ghostty_switcher" and GHOSTTY or ITERM2,
    windows = { { "w1", "[vm/api]" }, { "w2", "[main]" }, { "w3", "fish" } },
  }
  for k, v in pairs(setup or {}) do
    world[k] = v
  end
  for _, name in ipairs({ module, "switcher", "failure", "picker", "iterm2_api", "event_log" }) do
    package.loaded[name] = nil
  end
  package.preload.picker = function()
    return {
      new = function(opts)
        world.onPick = opts.onPick
        return {
          show = function(_, rows, at)
            table.insert(world.shown, { rows = rows, at = at })
          end,
          delete = function() end,
        }
      end,
    }
  end
  package.preload.iterm2_api = function()
    return {
      listWindows = function(seconds, callback)
        world.replySeconds = seconds
        callback(world.event)
      end,
      activateWindow = function(id)
        table.insert(world.activated, id)
      end,
    }
  end
  package.preload.event_log = function()
    return {
      new = function()
        return function(fmt, ...)
          local line = string.format(fmt, ...)
          table.insert(world.logged, line)
          note("module: %s", line)
        end,
          "/logs/switcher"
      end,
    }
  end
  _G.hs = stubHs()
  return require(module)
end

-- A mouse event of `kind`, of the middle button unless `button` says.
local function mouse(kind, flags, button)
  return {
    getProperty = function()
      return button or 2
    end,
    getType = function()
      return kind
    end,
    getFlags = function()
      return flags or {}
    end,
    location = function()
      return { x = 612.5, y = 603 }
    end,
  }
end

-- Press and release, then run what was left for after the tap: what each of
-- the two returned, true meaning the event went no further.
local function click(flags, button)
  assert(world.tap.running, "a click with the tap stopped")
  local down = world.tap.fn(mouse(DOWN, flags, button))
  local up = world.tap.fn(mouse(UP, flags, button))
  for _, fn in ipairs(world.timers) do
    fn()
  end
  world.timers = {}
  return down, up
end

-- Tell every app watcher, as macOS tells each one.
local function appEvent(name, event, application)
  for _, fn in ipairs(world.onApps) do
    fn(name, event, application)
  end
end

-- Ghostty moved `id` to the front of `windows` and macOS said so; the wait
-- for its list to catch up then ends. Its other windows stay as they were,
-- which is how the window left falls out of second place.
local function focusOn(id)
  for i, window in ipairs(world.windows) do
    if window[1] == id then
      table.insert(world.windows, 1, table.remove(world.windows, i))
      break
    end
  end
  world.focus.fn()
  assert(world.settle.pending, "a focus change did not start the wait")
  world.settle.pending = false
  world.settle.fn()
end

local function titlesShown()
  click()
  local rows = world.shown[#world.shown].rows
  local ids = {}
  for _, row in ipairs(rows) do
    table.insert(ids, row.id)
  end
  return table.concat(ids, " ")
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

test("a middle click over Ghostty opens the picker, the second row selected", function()
  load("ghostty_switcher")
  local down, up = click()
  assert(down == true and up == true, "the click reached the pane")
  assert(#world.shown == 1, "no picker")
  local shown = world.shown[1]
  assert(shown.at.selected == 2, "the second row is not selected")
  assert(shown.at.at.x == 612.5, "not opened at the click")
  assert(#shown.rows == 3, "not a row per window")
  local first, second = shown.rows[1], shown.rows[2]
  assert(first.id == "w1" and first.title == "[vm/api]" and first.detail == "current", "first row wrong")
  assert(second.id == "w2" and second.title == "[main]" and second.detail == "", "second row wrong")
end)

test("one window has only its own row to select", function()
  load("ghostty_switcher", { windows = { { "w1", "[vm/api]" } } })
  click()
  assert(world.shown[1].at.selected == 1, "selected a row that is not there")
end)

test("a drag between press and release stays swallowed", function()
  load("ghostty_switcher")
  assert(world.tap.fn(mouse(DOWN)) == true, "down reached the pane")
  assert(world.tap.fn(mouse(DRAGGED)) == true, "a drag reached the pane")
end)

test("a click with a modifier, or of another button, is left alone", function()
  load("ghostty_switcher")
  local down, up = click({ alt = true })
  assert(down == false and up == false, "a modified click was taken")
  down, up = click({}, 3)
  assert(down == false and up == false, "another button was taken")
  assert(#world.shown == 0, "a picker opened")
end)

test("a click over another app's window is left alone", function()
  load("ghostty_switcher", { underPointer = OTHER_PID })
  local down, up = click()
  assert(down == false and up == false, "another app's click was taken")
  assert(#world.shown == 0, "a picker opened")
end)

test("the tap runs only while its app is in front", function()
  load("ghostty_switcher", { front = "other" })
  assert(not world.tap.running, "the tap runs behind another app")
  appEvent("Ghostty", "activated", focusable())
  assert(world.tap.running, "the tap did not start")
  appEvent("Other", "activated", app("other"))
  assert(not world.tap.running, "the tap did not stop")
end)

test("a pick brings that window forward", function()
  load("ghostty_switcher")
  world.onPick("w2")
  assert(world.scripts[1]:find('first window whose id is "w2"', 1, true), "activated something else")
end)

test("a failed list is alerted by name, and no picker opens", function()
  load("ghostty_switcher", { scriptError = "Ghostty got an error (-1712)" })
  click()
  assert(#world.shown == 0, "a picker opened")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(world.alerts[1]:find("listing Ghostty's windows failed", 1, true), world.alerts[1])
end)

test("macOS refusing Hammerspoon says where to allow it", function()
  load("ghostty_switcher", { scriptError = "Not authorized (-1743)" })
  click()
  assert(world.alerts[1]:find("Privacy & Security > Automation", 1, true), world.alerts[1])
end)

test("a failed pick raises, for the picker to give the keyboard back", function()
  load("ghostty_switcher", { scriptError = "no such window" })
  local ok, err = pcall(world.onPick, "w2")
  assert(not ok, "it did not raise")
  assert(tostring(err):find("bringing window w2 forward failed", 1, true), tostring(err))
end)

-- Measured 2026-11-04: on a jump between fullscreen windows Ghostty's own
-- order put a third window second, not the one left, in both directions.
test("the second row is the window left, whatever Ghostty's order says", function()
  load("ghostty_switcher", { windows = { { "A", "a" }, { "w1", "b" }, { "w2", "c" }, { "C", "d" } } })
  focusOn("A")
  focusOn("C")
  -- Ghostty's list now reads C, A...; put it as measured: C, w1, w2, A.
  world.windows = { { "C", "d" }, { "w1", "b" }, { "w2", "c" }, { "A", "a" } }
  assert(titlesShown() == "C A w1 w2", "not by recency: " .. titlesShown())
  focusOn("A")
  world.windows = { { "A", "a" }, { "w1", "b" }, { "w2", "c" }, { "C", "d" } }
  assert(titlesShown() == "A C w1 w2", "the flip back is lost: " .. titlesShown())
end)

test("windows not focused since load keep Ghostty's order, after those that were", function()
  load("ghostty_switcher", { windows = { { "A", "a" }, { "B", "b" }, { "C", "c" } } })
  assert(titlesShown() == "A B C", titlesShown())
  focusOn("C")
  assert(titlesShown() == "C A B", titlesShown())
  local said = false
  for _, line in ipairs(world.logged) do
    said = said or line == "focused C"
  end
  assert(said, "the focus change was not logged")
end)

test("the first row is the window in front, a focus event missed or not", function()
  load("ghostty_switcher", { windows = { { "A", "a" }, { "B", "b" } } })
  focusOn("B")
  -- Ghostty changed its front window with no event seen, or none settled yet.
  world.windows = { { "A", "a" }, { "B", "b" } }
  assert(titlesShown() == "A B", titlesShown())
end)

test("a window closed leaves the history, and one opened joins it", function()
  load("ghostty_switcher", { windows = { { "A", "a" }, { "B", "b" } } })
  focusOn("B")
  world.windows = { { "N", "n" }, { "B", "b" } }
  world.focus.fn()
  world.settle.pending = false
  world.settle.fn()
  assert(titlesShown() == "N B", titlesShown())
end)

test("focus changes wait for Ghostty, and a read with no window is no error", function()
  load("ghostty_switcher", { windows = {} })
  assert(world.settle.seconds > 0.2, "shorter than Ghostty's lag of up to 185 ms")
  world.focus.fn()
  world.settle.fn()
  assert(#world.alerts == 0, "alerted: " .. tostring(world.alerts[1]))
end)

test("Ghostty quit: no read that would launch it, and watching starts again", function()
  load("ghostty_switcher", { windows = { { "A", "a" }, { "B", "b" } } })
  focusOn("B")
  local first = world.focus
  world.focus.fn()
  world.ghosttyRuns = false
  appEvent("Ghostty", "terminated", app(GHOSTTY))
  assert(not first.running, "still watching a Ghostty that quit")
  assert(not world.settle.pending, "a read still pending")
  local asked = #world.scripts
  world.settle.fn()
  assert(#world.scripts == asked, "asked Ghostty, which would launch it")

  world.ghosttyRuns = true
  appEvent("Ghostty", "activated", focusable())
  assert(world.focus ~= first and world.focus.running, "not watching the new Ghostty")
  appEvent("Ghostty", "activated", focusable())
  assert(#world.focusWatchers == 2, "a second watcher on the same Ghostty")
end)

test("Ghostty not running at load: nothing is watched until it comes", function()
  load("ghostty_switcher", { ghosttyRuns = false, front = "other" })
  assert(world.focus == nil, "watching nothing")
  world.ghosttyRuns = true
  appEvent("Ghostty", "activated", focusable())
  assert(world.focus.running, "not watching")
end)

test("Ghostty quitting before it was ever activated is no error", function()
  load("ghostty_switcher", { ghosttyRuns = false, front = "other" })
  appEvent("Ghostty", "terminated", app(GHOSTTY))
  assert(world.focus == nil, "watching something")
end)

test("iTerm2's rows and picks still go through its API", function()
  load("iterm2_switcher", {
    event = {
      current = "a",
      windows = {
        { window = "a", title = "~/.dotfiles", number = 1, tabs = 3 },
        { window = "b", title = "", number = 6, tabs = 1 },
      },
    },
  })
  click()
  assert(world.replySeconds == 1, "no time limit on the reply")
  local rows = world.shown[1].rows
  assert(rows[1].detail == "3 tabs (current)", rows[1].detail)
  assert(rows[2].title == "window 6" and rows[2].detail == "1 tab", rows[2].title)
  world.onPick("b")
  assert(world.activated[1] == "b", "the pick did not reach the API")
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
