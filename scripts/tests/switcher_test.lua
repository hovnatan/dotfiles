-- switcher.lua, through the real ghostty_switcher.lua,
-- against Hammerspoon doubles:
--
--   test --click()--> doubled tap --> onOtherMouse --> doubled timer
--                                                        |
--                       doubled picker <-- rows <-- opts.list
--                            |
--   test --pick()------------+--> opts.activate --> doubled AltTab CLI
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

local GHOSTTY = "com.mitchellh.ghostty"
local APP_PID, OTHER_PID = 500, 900
local DOWN, DRAGGED, UP = 1, 2, 3

-- What the module did, for the asserts.
local world

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
      watcher = {
        activated = "activated",
        new = function(fn)
          table.insert(world.onApps, fn)
          return { start = function() end }
        end,
      },
    },
    timer = {
      doAfter = function(_, fn)
        table.insert(world.timers, fn)
        return {}
      end,
    },
    -- AltTab's CLI: a command is noted, and answers as world says. Its reply
    -- stands for the JSON, so decode hands the table back.
    execute = function(command)
      table.insert(world.commands, command)
      if world.cliError then
        return world.cliError .. "\n", nil, "exit", 1
      end
      return world.reply or "the list", true, "exit", 0
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

-- A window as AltTab lists it, of Ghostty unless `bundle` says.
local function ghostty(id, title, order, bundle)
  return { id = id, title = title, lastFocusOrder = order, appBundleId = bundle or GHOSTTY }
end

local function load(module, setup)
  world = {
    alerts = {},
    logged = {},
    shown = {},
    commands = {},
    timers = {},
    activated = {},
    onApps = {},
    underPointer = APP_PID,
    front = GHOSTTY,
    windows = { ghostty(101, "[vm/api]", 0), ghostty(102, "[main]", 1), ghostty(103, "fish", 2) },
  }
  for k, v in pairs(setup or {}) do
    world[k] = v
  end
  for _, name in ipairs({ module, "switcher", "failure", "picker", "event_log" }) do
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

local function idsShown()
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
  assert(first.id == "101" and first.title == "[vm/api]" and first.detail == "current", "first row wrong")
  assert(second.id == "102" and second.title == "[main]" and second.detail == "", "second row wrong")
end)

test("one window has only its own row to select", function()
  load("ghostty_switcher", { windows = { ghostty(101, "[vm/api]", 0) } })
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
  appEvent("Ghostty", "activated", app(GHOSTTY))
  assert(world.tap.running, "the tap did not start")
  appEvent("Other", "activated", app("other"))
  assert(not world.tap.running, "the tap did not stop")
end)

test("a pick brings that window forward", function()
  load("ghostty_switcher")
  world.onPick("102")
  assert(world.commands[1]:find(" --focus=102 ", 1, true), "activated something else: " .. world.commands[1])
end)

test("what AltTab says goes in the alert, to give the reason a list failed", function()
  load("ghostty_switcher", { cliError = "AltTab.app needs to be running for CLI commands to work" })
  click()
  assert(#world.shown == 0, "a picker opened")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(
    world.alerts[1]:find("listing windows failed (exit 1): AltTab.app needs to be running", 1, true),
    world.alerts[1]
  )
end)

test("a failed pick raises, for the picker to give the keyboard back", function()
  load("ghostty_switcher", { cliError = "Couldn't execute command. Is it correct?" })
  local ok, err = pcall(world.onPick, "102")
  assert(not ok, "it did not raise")
  assert(tostring(err):find("bringing window 102 forward failed", 1, true), tostring(err))
end)

-- A reply that fails to parse is what a failed AltTab looks like if it exits 0.
test("a reply that is not the list is alerted, and no picker opens", function()
  load("ghostty_switcher", { reply = "\n" })
  click()
  assert(#world.shown == 0, "a picker opened")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(world.alerts[1]:find("window list is not as expected", 1, true), world.alerts[1])
end)

test("no Ghostty window in the list is alerted, not an empty picker", function()
  load("ghostty_switcher", { windows = { ghostty(201, "Slack", 0, "com.tinyspeck.slackmacgap") } })
  click()
  assert(#world.shown == 0, "a picker opened")
  assert(world.alerts[1]:find("AltTab lists no Ghostty window", 1, true), tostring(world.alerts[1]))
end)

-- AltTab's list is every app's and not in focus order (2026-11-06: 1, 2, 0).
test("the rows are Ghostty's alone, the most recently focused first", function()
  load("ghostty_switcher", {
    windows = {
      ghostty(101, "image-loading", 4),
      ghostty(102, "ai-agent", 7),
      ghostty(201, "Slack", 0, "com.tinyspeck.slackmacgap"),
      ghostty(103, "dotfiles", 1),
    },
  })
  assert(idsShown() == "103 101 102", idsShown())
  local rows = world.shown[#world.shown].rows
  assert(rows[1].detail == "current" and rows[2].detail == "", "the window in front is not the one marked")
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
