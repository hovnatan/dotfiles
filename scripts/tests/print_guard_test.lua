-- print_guard.lua against a double of hs.ipc's print hook:
--
--   test --print()--> guard --> the double's hook --> Console (a list)
--                                    '--> each client's remote:sendMessage
--
-- The double is hs.ipc's printReplacement and its print_enter, print_exit
-- and print_inside as Hammerspoon 1.1.1 has them (extensions/hs/ipc.lua),
-- with hs.logger's warning written as the print() it ends in. The first
-- test shows the double failing, unguarded, the way the real one did; the
-- check against a running Hammerspoon is in print_guard.lua's header.
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

-- The lines the Console got, and the double of hs.ipc that put them there.
local console, ipc

local function ipcDouble()
  local module = { insidePrintInstances = {}, __registeredCLIInstances = {} }
  module.print_enter = function(id)
    module.insidePrintInstances[id] = (module.insidePrintInstances[id] or 0) + 1
  end
  module.print_exit = function(id)
    if module.insidePrintInstances[id] then
      module.insidePrintInstances[id] = module.insidePrintInstances[id] - 1
      if module.insidePrintInstances[id] == 0 then
        module.insidePrintInstances[id] = nil
      end
    end
  end
  module.print_inside = function(id)
    local count = module.insidePrintInstances[id]
    return count and count > 0
  end

  module.printReplacement = function(...)
    local text = table.concat({ ... }, "\t")
    table.insert(console, text)
    for id, v in pairs(module.__registeredCLIInstances) do
      if v._cli.console and v.print and not v._cli.quietMode then
        if module.print_inside(id) then
          -- log.w(...): hs.logger formats it and calls print.
          print(string.format("Instance of [%s] already recursing, refusing request.", id))
        else
          module.print_enter(id)
          v._cli.remote:sendMessage(text .. "\n")
          module.print_exit(id)
        end
      end
    end
  end
  return module
end

-- A connected `hs`, registered as `id`: alive until c.alive is false,
-- failing its sends with c.sendError while that is set. opts.quiet is -q;
-- opts.noRemote one whose port could not be opened.
local function client(id, opts)
  opts = opts or {}
  local c = { alive = true, got = {}, deleted = false }
  local remote = {
    isValid = function()
      return c.alive
    end,
    sendMessage = function(_, text)
      if not c.alive then
        error("ipc port is no longer valid (early)")
      elseif c.sendError then
        error(c.sendError)
      end
      table.insert(c.got, text)
    end,
    delete = function()
      c.deleted = true
    end,
  }
  ipc.__registeredCLIInstances[id] = {
    _cli = { console = "none", quietMode = opts.quiet or false, remote = not opts.noRemote and remote or nil },
    print = function() end,
  }
  return c
end

-- A fresh hs.ipc whose hook is the global print, as after require("hs.ipc");
-- then print_guard.lua on top of it unless `unguarded`.
local function load(unguarded)
  console = {}
  ipc = ipcDouble()
  package.loaded["hs.ipc"] = ipc
  print = ipc.printReplacement -- luacheck: ignore
  package.loaded["print_guard"] = nil
  if not unguarded then
    require("print_guard")
  end
end

local function registered(id)
  return ipc.__registeredCLIInstances[id] ~= nil
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

test("unguarded, a killed client breaks print the way it did live", function()
  load(true)
  local c = client("a")
  c.alive = false
  local ok, err = pcall(print, "one")
  assert(not ok and tostring(err):find("no longer valid", 1, true), "1st print: " .. tostring(err))
  ok, err = pcall(print, "two")
  assert(not ok and tostring(err):find("stack overflow", 1, true), "2nd print: " .. tostring(err))
end)

test("a killed client is unregistered before the line is sent", function()
  load()
  local c = client("a")
  c.alive = false
  print("one")
  print("two")
  assert(console[1] == "one" and console[2] == "two" and #console == 2, "Console: " .. table.concat(console, " | "))
  assert(not registered("a"), "still registered")
  assert(c.deleted, "its port was not deleted")
  assert(#c.got == 0, "it was sent to")
end)

test("a client killed between two prints, and the mark an earlier failure left", function()
  load()
  local c = client("a")
  print("one")
  assert(c.got[1] == "one\n", "alive, it got: " .. tostring(c.got[1]))
  c.alive = false
  ipc.insidePrintInstances["a"] = 1
  print("two")
  assert(not registered("a") and ipc.insidePrintInstances["a"] == nil, "still registered, or marked")
  assert(#console == 2, "Console: " .. table.concat(console, " | "))
end)

test("the clients that live get every line; a quiet one none", function()
  load()
  local dead, live, quiet = client("dead"), client("live"), client("quiet", { quiet = true })
  dead.alive = false
  print("one", "more")
  assert(live.got[1] == "one\tmore\n", "the live one got: " .. tostring(live.got[1]))
  assert(#quiet.got == 0, "the quiet one was sent to")
  assert(registered("live") and registered("quiet") and not registered("dead"), "the wrong ones are registered")
  assert(not live.deleted and not quiet.deleted, "a live port was deleted")
end)

test("a client with no port is unregistered", function()
  load()
  client("a", { noRemote = true })
  print("one")
  assert(not registered("a"), "still registered")
  assert(console[1] == "one", "Console: " .. table.concat(console, " | "))
end)

test("a send that fails on a live port raises as itself, at every print", function()
  load()
  local c = client("a")
  c.sendError = "send timed out"
  for attempt = 1, 3 do
    local ok, err = pcall(print, "line " .. attempt)
    assert(not ok and tostring(err):find("send timed out", 1, true), "print " .. attempt .. ": " .. tostring(err))
  end
  assert(registered("a"), "a live client was unregistered")

  -- Over, and print is whole again: no mark was left behind.
  c.sendError = nil
  print("after")
  assert(c.got[1] == "after\n", "after the failure it got: " .. tostring(c.got[1]))
  assert(#console == 4, "Console: " .. table.concat(console, " | "))
end)

note("%d failed", failures)
os.exit(failures == 0 and 0 or 1)
