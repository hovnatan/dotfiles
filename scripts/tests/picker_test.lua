-- picker.lua, the real module and page text, against Hammerspoon doubles:
--
--   test --show()--> real picker.lua --> doubled webview, its calls in world.calls
--   test --say()---> the page's messages, as the content callback gets them
--   test --expire()--> the doubled timer, as if the page never answered
--
-- The frames themselves cannot be doubled: that an opaque panel shows the new
-- rows was measured on a real panel (the top of picker.lua).
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

-- What the module did, for the asserts.
local world

local function viewDouble()
  local view = {}
  -- Every setter chains, as hs.webview's do; those the asserts read are noted.
  for _, name in ipairs({
    "windowStyle",
    "allowTextEntry",
    "transparent",
    "shadow",
    "level",
    "behavior",
    "html",
    "frame",
  }) do
    view[name] = function(self)
      return self
    end
  end
  function view.navigationCallback(self, fn)
    world.navigate = fn
    return self
  end
  function view.windowCallback(self, fn)
    world.onWindow = fn
    return self
  end
  function view.alpha(self, value)
    table.insert(world.calls, "alpha " .. value)
    world.alpha = value
    return self
  end
  function view.show(self)
    table.insert(world.calls, "show")
    return self
  end
  function view.hide(self)
    table.insert(world.calls, "hide")
    return self
  end
  function view.evaluateJavaScript(_, code, callback)
    table.insert(world.calls, code:match("^%w+"))
    table.insert(world.scripts, code)
    if callback then
      callback(world.rendered or 1, nil)
    end
  end
  return view
end

local function app(bundle)
  return {
    bundleID = function()
      return bundle
    end,
    activate = function()
      table.insert(world.activated, bundle)
    end,
  }
end

local function stubHs()
  return {
    configdir = repo .. "/home/.hammerspoon",
    inspect = tostring,
    alert = {
      show = function(msg)
        table.insert(world.alerts, msg)
        note("alert: %s", msg)
      end,
    },
    webview = {
      usercontent = {
        new = function()
          return {
            setCallback = function(_, fn)
              world.onMessage = fn
            end,
          }
        end,
      },
      new = function()
        return viewDouble()
      end,
    },
    drawing = {
      windowLevels = { popUpMenu = 101 },
      windowBehaviors = { moveToActiveSpace = 2, fullScreenAuxiliary = 256 },
    },
    geometry = {
      point = function(x, y)
        return {
          x = x,
          y = y,
          inside = function()
            return true
          end,
        }
      end,
    },
    screen = {
      allScreens = function()
        local bounds = { x = 0, y = 0, w = 1920, h = 1080 }
        return {
          {
            fullFrame = function()
              return bounds
            end,
            frame = function()
              return bounds
            end,
          },
        }
      end,
    },
    host = {
      interfaceStyle = function()
        return "Dark"
      end,
    },
    json = {
      encode = function()
        return "{}"
      end,
    },
    application = {
      frontmostApplication = function()
        return app("com.mitchellh.ghostty")
      end,
    },
    focus = function() end,
    timer = {
      doAfter = function(seconds, fn)
        local timer = { seconds = seconds, fn = fn, running = true }
        function timer.stop(self)
          self.running = false
        end
        world.timer = timer
        return timer
      end,
    },
  }
end

local function load()
  world = { alerts = {}, calls = {}, scripts = {}, activated = {}, cancelled = 0, picked = {} }
  for _, name in ipairs({ "picker", "failure", "event_log" }) do
    package.loaded[name] = nil
  end
  package.preload.event_log = function()
    return {
      new = function()
        return function(fmt, ...)
          note("module: " .. fmt, ...)
        end, "/logs/picker"
      end,
    }
  end
  _G.hs = stubHs()
  local p = require("picker").new({
    onPick = function(id)
      table.insert(world.picked, id)
    end,
    onCancel = function()
      world.cancelled = world.cancelled + 1
    end,
  })
  world.navigate("didFinishNavigation")
  return p
end

local function open(p)
  p:show({ { id = "1", title = "a", detail = "" } }, { at = { x = 700, y = 500 }, selected = 1 })
end

local function say(body)
  world.onMessage({ body = body })
end

-- The time limit runs out, its errors caught as Hammerspoon's timers would.
local function expire()
  assert(world.timer.running, "no time limit running")
  world.timer.running = false
  world.timer.fn()
end

-- `name`'s place in the calls so far, the last such.
local function placeOf(name)
  local place
  for i, call in ipairs(world.calls) do
    if call == name then
      place = i
    end
  end
  return place
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

test("an opening comes up transparent, after its rows are in the page", function()
  local p = load()
  open(p)
  assert(placeOf("render") < placeOf("alpha 0"), "transparent before the rows went in")
  assert(placeOf("alpha 0") < placeOf("show"), "shown opaque, with the last opening's frame")
  assert(placeOf("show") < placeOf("whenPainted"), "asked before showing, when no frame comes")
  assert(world.alpha == 0, "seen before it painted")
end)

test("it is made opaque when its page has painted, and the limit stops", function()
  local p = load()
  open(p)
  say({ action = "painted", opening = 1 })
  assert(world.alpha == 1, "not revealed")
  assert(not world.timer.running, "the limit would still close it")
end)

test("each opening is waited for anew", function()
  local p = load()
  open(p)
  say({ action = "painted", opening = 1 })
  say({ action = "pick", id = "1" })
  open(p)
  assert(world.alpha == 0, "the second opening is seen at once, with the first one's frame")
  assert(world.scripts[#world.scripts] == "whenPainted(2)", world.scripts[#world.scripts])
end)

test("an earlier opening's painted does not reveal this one", function()
  local p = load()
  open(p)
  say({ action = "cancel" })
  open(p)
  say({ action = "painted", opening = 1 })
  assert(world.alpha == 0, "revealed by a frame of the last opening")
  assert(world.timer.running, "the limit stopped for nothing")
end)

test("a painted after closing is dropped", function()
  local p = load()
  open(p)
  say({ action = "cancel" })
  say({ action = "painted", opening = 1 })
  assert(world.alpha == 0, "revealed a closed panel")
  assert(#world.alerts == 0, "alerted: " .. tostring(world.alerts[1]))
end)

test("closing stops the limit, so it cannot close a later moment's panel", function()
  local p = load()
  open(p)
  say({ action = "cancel" })
  assert(not world.timer.running, "still running")
end)

test("a page that never paints gives the keyboard back, and says so", function()
  local p = load()
  open(p)
  assert(world.timer.seconds <= 1, "the keyboard held unseen too long: " .. world.timer.seconds)
  expire()
  assert(placeOf("hide"), "still up, unseen, with the keyboard")
  assert(world.activated[1] == "com.mitchellh.ghostty", "the keyboard stayed with the hidden panel")
  assert(world.cancelled == 1, "onCancel not told")
  assert(#world.alerts == 1, "alerted " .. #world.alerts .. " times")
  assert(world.alerts[1]:find("did not paint", 1, true), world.alerts[1])
  assert(p.open == false, "still open")
end)

test("a message the module does not know is alerted", function()
  local p = load()
  open(p)
  say({ action = "repaint" })
  assert(world.alerts[1]:find("does not know", 1, true), tostring(world.alerts[1]))
end)

-- `-->` in the page's header comment ended it there, and the rest became text
-- above the rows, 72 px of it (2026-11-06).
test("the page's header comment ends once, at its end", function()
  local f = assert(io.open(repo .. "/home/.hammerspoon/picker.html"))
  local page = f:read("a")
  f:close()
  local header = assert(page:match("^(.-)<html>"), "no <html> in the page")
  local _, ends = header:gsub("%-%->", "")
  assert(ends == 1, "the comment is closed " .. ends .. " times")
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
