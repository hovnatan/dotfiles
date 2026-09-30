-- Real banner module, deterministic scheduling:
--
-- AX arrival -> real queue/snapshot logic -> explicit task completion
-- focus event -> explicit snapshot        -> recorded banner dismissal
--
-- The transport and macOS UI are doubles. Counters, generations, callbacks,
-- ownership and recovery all execute the production module unchanged.
local repo = assert(arg[1], "pass the repo path")
local file = assert(io.open(assert(arg[2], "pass the event log path"), "a"))
file:setvbuf("line")
local scenario, now = "setup", 100
local function log(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [" .. scenario .. "] " .. string.format(fmt, ...)
  file:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end

-- Timers and observers only fire when the test invokes their callbacks.
local function object(fn)
  return {
    fn = fn,
    start = function(self)
      return self
    end,
    stop = function(self)
      self.stopped = true
      return self
    end,
    terminate = function(self)
      self.terminated = true
      return self
    end,
    callback = function(self, cb)
      self.fn = cb
      return self
    end,
    addWatcher = function(self)
      return self
    end,
    pid = function()
      return 1
    end,
  }
end

local function fresh()
  now = 100
  local ui = { banners = {}, closed = {} }
  package.loaded.clear_notifications = {
    pid = function()
      return 2
    end,
    banners = function()
      return ui.banners, 1
    end,
    press = function(banner)
      assert(not ui.closed[banner.id], "banner was closed twice")
      ui.closed[banner.id] = true
      for i, b in ipairs(ui.banners) do
        if b.id == banner.id then
          table.remove(ui.banners, i)
          break
        end
      end
    end,
  }
  package.loaded.event_log = {
    new = function()
      return log, repo .. "/.logs"
    end,
  }
  _G.hs = {
    configdir = repo .. "/home/.hammerspoon",
    alert = {
      show = function(msg)
        log("alert: %s", msg)
      end,
    },
    -- Pass decoded task payloads directly. A string represents broken JSON.
    json = {
      decode = function(value)
        assert(type(value) == "table", "invalid JSON")
        return value
      end,
    },
    timer = {
      secondsSinceEpoch = function()
        return now
      end,
      doAfter = function(_, fn)
        return object(fn)
      end,
      delayed = {
        new = function(_, fn)
          return object(fn)
        end,
      },
    },
    task = {
      new = function(_, fn)
        return object(fn)
      end,
    },
    application = {
      applicationsForBundleID = function()
        return { object() }
      end,
      watcher = { new = object, launched = 1, terminated = 2 },
    },
    axuielement = {
      observer = {
        new = function()
          return object()
        end,
      },
      applicationElement = function()
        return {}
      end,
      applicationElementForPID = function()
        return {}
      end,
    },
  }
  return assert(loadfile(repo .. "/home/.hammerspoon/iterm2_bell_banners.lua"))(), ui
end

local function data(a, b, shown, aTab, bTab)
  shown = shown or "VISIBLE"
  return {
    frontmost = true,
    current = shown,
    sessions = {
      { sessionId = "VISIBLE", sessionName = "visible", tabNumber = 1, bells = 0, visible = shown == "VISIBLE" },
      { sessionId = "SESSION_A", sessionName = "a", tabNumber = aTab or 2, bells = a, visible = shown == "SESSION_A" },
      { sessionId = "SESSION_B", sessionName = "b", tabNumber = bTab or 3, bells = b, visible = shown == "SESSION_B" },
    },
  }
end

local function complete(m, snapshot)
  assert(m.task, "expected an in-flight snapshot").fn(0, snapshot, "")
end

local function arrive(m, ui, id, tab)
  local desc = "iTerm2, Bell, Session test #" .. tab .. " just rang a bell!"
  table.insert(ui.banners, { id = id, desc = desc, subrole = "AXNotificationCenterAlert" })
  m.ncObserver.fn(nil, {
    attributeValue = function(_, name)
      return assert(({ AXIdentifier = id, AXDescription = desc, AXSubrole = "AXNotificationCenterAlert" })[name])
    end,
  })
end

local function focus(m, snapshot)
  m.focusTimer.fn()
  complete(m, snapshot)
end

local function owner(m, banner, sid)
  assert(m.pending[banner] and m.pending[banner][sid], banner .. " lost owner " .. sid)
end

local function raises(pattern, fn)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), "expected error: " .. pattern .. "; got " .. tostring(err))
end

local passed, failed = 0, 0
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

test("ordinary bell closes when its tab is visited", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 0))
  owner(m, "BANNER_A", "SESSION_A")
  focus(m, data(1, 0, "SESSION_A"))
  assert(ui.closed.BANNER_A and not m.pending.BANNER_A)
end)

test("later arrival waits for a newer snapshot", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  arrive(m, ui, "BANNER_B", 3)
  complete(m, data(1, 0))
  assert(#m.queue == 1 and m.queue[1].id == "BANNER_B")
  complete(m, data(1, 1))
  owner(m, "BANNER_A", "SESSION_A")
  owner(m, "BANNER_B", "SESSION_B")
  assert(#m.queue == 0)
  focus(m, data(1, 1, "SESSION_A"))
  assert(not ui.closed.BANNER_B, "unvisited B was dismissed")
  focus(m, data(1, 1, "SESSION_B"))
  assert(ui.closed.BANNER_A and ui.closed.BANNER_B)
end)

test("focus snapshot cannot erase evidence of a newer arrival", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  m.focusTimer.fn()
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 0, "SESSION_A"))
  assert(m.bells.SESSION_A == 1 and #m.queue == 1)
  now = now + 20
  complete(m, data(1, 0))
  owner(m, "BANNER_A", "SESSION_A")
end)

test("recent absorbed rise survives a delayed resolution", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  focus(m, data(1, 0, "SESSION_A"))
  now = now + 1
  arrive(m, ui, "BANNER_A", 2)
  now = now + 20
  complete(m, data(1, 0))
  owner(m, "BANNER_A", "SESSION_A")
end)

test("snapshot failure recovers on focus without another bell", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  raises("(-1728)", function()
    m.task.fn(1, "", "Can't get object. (-1728)")
  end)
  assert(#m.queue == 1 and not m.task)
  now = now + 20
  focus(m, data(1, 0, "SESSION_A"))
  assert(#m.queue == 0 and #m.waiting == 0 and ui.closed.BANNER_A)
end)

test("failed work precedes and deduplicates newer callbacks", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  arrive(m, ui, "BANNER_B", 3)
  m.focusTimer.fn()
  raises("(-1743)", function()
    m.task.fn(1, "", "Not authorized. (-1743)")
  end)
  assert(#m.waiting == 2, "expected one resolver and one focus callback")
  focus(m, data(1, 1))
  owner(m, "BANNER_A", "SESSION_A")
  owner(m, "BANNER_B", "SESSION_B")
  assert(#m.queue == 0 and #m.waiting == 0)
end)

test("timeout preserves work and ignores the late completion", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  local old = m.task
  raises("took over 5s", m.queryTimer.fn)
  assert(old.terminated and #m.waiting == 1)
  m.focusTimer.fn()
  local current = m.task
  old.fn(1, "", "terminated")
  assert(m.task == current, "late completion replaced the current task")
  complete(m, data(1, 0, "SESSION_A"))
  assert(ui.closed.BANNER_A and #m.queue == 0)
end)

test("invalid JSON preserves resolution for the next event", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  raises("printed no JSON", function()
    complete(m, "broken")
  end)
  focus(m, data(1, 0, "SESSION_A"))
  assert(ui.closed.BANNER_A)
end)

test("tab insertion before resolution retains the session", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  local moved = data(1, 0, nil, 3, 4)
  table.insert(
    moved.sessions,
    { sessionId = "INSERTED", sessionName = "new", tabNumber = 2, bells = 0, visible = false }
  )
  complete(m, moved)
  owner(m, "BANNER_A", "SESSION_A")
  focus(m, data(1, 0, "SESSION_A", 3, 4))
  assert(ui.closed.BANNER_A)
end)

test("tab swap cannot assign A only to the replacement at its old position", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 1, nil, 3, 2))
  owner(m, "BANNER_A", "SESSION_A")
  owner(m, "BANNER_A", "SESSION_B")
  focus(m, data(1, 1, "SESSION_B", 3, 2))
  assert(not ui.closed.BANNER_A)
  focus(m, data(1, 1, "SESSION_A", 3, 2))
  assert(ui.closed.BANNER_A)
end)

test("closed owner releases its resolved banner", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 0))
  local closed = data(1, 0)
  table.remove(closed.sessions, 2)
  focus(m, closed)
  assert(ui.closed.BANNER_A)
end)

test("iTerm2 exit drops failed callers without relaunching it", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  m.focusTimer.fn()
  complete(m, { gone = true })
  assert(#m.queue == 0 and #m.waiting == 0 and not m.task)
end)

-- The 2026-09-30 miss: a focus scan sees no banner for an instant while the
-- banner stays on screen. Pending must survive it, so the visit closes it.
test("one empty scan keeps pending; the banner closes on the visit", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 0))
  local shown = ui.banners
  ui.banners = {}
  local background = data(1, 0)
  background.frontmost = false
  focus(m, background)
  focus(m, background) -- a second scan within PRUNE_CONFIRM is not confirmation
  assert(m.pending.BANNER_A and m.emptySince, "an unconfirmed empty scan emptied pending")
  ui.banners = shown
  now = now + 5
  focus(m, data(1, 0, "SESSION_A"))
  assert(ui.closed.BANNER_A and not m.pending.BANNER_A and not m.emptySince)
end)

test("absence at two focus changes apart prunes a dismissed banner", function()
  local m, ui = fresh()
  complete(m, data(0, 0))
  arrive(m, ui, "BANNER_A", 2)
  complete(m, data(1, 0))
  ui.banners = {} -- clicked, or cleared with alt+0
  focus(m, data(1, 0))
  assert(m.pending.BANNER_A, "pruned on a single scan")
  now = now + 2
  focus(m, data(1, 0))
  assert(not m.pending.BANNER_A and not m.emptySince)
  focus(m, data(1, 0, "SESSION_A"))
  assert(not ui.closed.BANNER_A)
end)

-- The real clear_notifications.lua against a stub Notification Center
-- element: an empty window list is an empty screen, a nil one is a failed
-- accessibility read and must not pass for it.
local function realNotifications(windows)
  local element = {
    attributeValue = function(_, name)
      return ({ AXTitle = "Notification Center", AXWindows = windows })[name]
    end,
  }
  _G.hs = {
    hotkey = {
      bind = function() end,
    },
    alert = {
      show = function(msg)
        log("alert: %s", msg)
      end,
    },
    timer = {
      doAfter = function(_, fn)
        return object(fn)
      end,
    },
    axuielement = {
      applicationElementForPID = function()
        return element
      end,
    },
    application = {
      applicationsForBundleID = function()
        return { object() }
      end,
    },
  }
  package.loaded.clear_notifications = nil
  return assert(loadfile(repo .. "/home/.hammerspoon/clear_notifications.lua"))()
end

test("an unreadable window list raises; an empty one is an empty screen", function()
  local found, windows = realNotifications({}).banners()
  assert(#found == 0 and windows == 0)
  raises("could not be read", function()
    realNotifications(nil).banners()
  end)
end)

scenario = "summary"
log("%d passed, %d failed", passed, failed)
file:close()
if failed > 0 then
  os.exit(1)
end
