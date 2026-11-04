-- Ghostty's window picker on a middle click (switcher.lua), its windows from
-- Ghostty's AppleScript:
--
--   up: LIST_WINDOWS --> { { id, name }, ... }, Ghostty's order
--        v
--   a row per window, the most recently focused first (byRecency)
--        | picked
--        v
--   ACTIVATE <id>: to front, switching to its Space
--
--   focused window changed (macOS) --SETTLE_SECONDS--> FRONT_WINDOW --> recent
--
-- The order is kept here, as Ghostty's is no history: from A to C across
-- fullscreen Spaces it read C, w1, w2, A, and back again A, w1, w2, C, so the
-- window left was never second (measured 2026-11-04). Its first window is
-- right, though: macOS says when focus moves, once a jump, none for windows
-- passed over, and the first window is then read for what it moved to. The
-- wait is for Ghostty: its list still shows the old window at the event, and
-- caught up 133-183 ms later over 6 jumps. The history lasts while Ghostty and
-- Hammerspoon do; a window not focused since sorts after, in Ghostty's order.
--
-- All run in Hammerspoon's process and hold its one thread, 34 ms and 20 ms
-- for a list and an activate (2026-11-04), so a timeout bounds a hung Ghostty. In-process, a
-- failure raises where the picker can give the keyboard back; a task's would
-- come too late. Not hs.window, which sees only the current Space's windows.
--
-- The first run asks macOS to let Hammerspoon control Ghostty, as a snapshot's
-- does (ghostty_snapshots.lua). A window's name carries Ghostty's bell mark,
-- which here says which window rang.
local GHOSTTY = "com.mitchellh.ghostty"

-- One Apple event for all windows: ids and names read apart could pair a name
-- with the wrong window, as the order moves, and a read per window took 500 ms
-- for 8 (2026-11-04). The loop is over records already here, no more events.
local LIST_WINDOWS = [[
with timeout of 1 seconds
  tell application "Ghostty"
    set found to properties of every window
    set rows to {}
    repeat with p in found
      set end of rows to {id of p, name of p}
    end repeat
    return rows
  end tell
end timeout
]]
-- "" for no window, as closing the last one moves focus too.
local FRONT_WINDOW = [[
with timeout of 1 seconds
  tell application "Ghostty"
    if (count of windows) is 0 then return ""
    return id of first window
  end tell
end timeout
]]
local ACTIVATE = [[
with timeout of 1 seconds
  tell application "Ghostty"
    activate window (first window whose id is "%s")
  end tell
end timeout
]]

-- Twice Ghostty's lag, so a read lands after it; the wait restarts on each
-- change, so a window held for less is passed through, not visited.
local SETTLE_SECONDS = 0.4

local S

-- Window ids, the most recently focused first.
local recent = {}

local function visit(id)
  for i, seen in ipairs(recent) do
    if seen == id then
      table.remove(recent, i)
      break
    end
  end
  table.insert(recent, 1, id)
end

-- Run `script`: its result, else alerted and raised, naming `what`. A -1743
-- is macOS refusing Hammerspoon, which the alert says how to allow.
local function ask(script, what)
  local ok, result, raw = hs.osascript.applescript(script)
  if ok then
    return result
  end
  local said = hs.inspect(raw)
  local hint = said:find("-1743", 1, true)
      and "; allow Hammerspoon to control Ghostty in System Settings > Privacy & Security > Automation"
    or ""
  S.fail(string.format("%s failed: %s%s", what, said, hint))
end

-- `windows`, in Ghostty's order, by `recent`, those not in it after, in the
-- order given. The window in front counts as visited: it is the one thing
-- Ghostty's order says for sure, and an event may be missed or not settled.
-- `recent` becomes the result, which drops the windows closed.
--   recent { "C", "A" }, windows { C, w1, A } -> { C, A, w1 }
local function byRecency(windows)
  visit(windows[1][1])
  local rank = {}
  for i, id in ipairs(recent) do
    rank[id] = i
  end
  local place = {}
  for i, window in ipairs(windows) do
    place[window[1]] = (rank[window[1]] or #recent + 1) * (#windows + 1) + i
  end
  local sorted = { table.unpack(windows) }
  table.sort(sorted, function(a, b)
    return place[a[1]] < place[b[1]]
  end)
  recent = {}
  for _, window in ipairs(sorted) do
    table.insert(recent, window[1])
  end
  return sorted
end

-- A row per window, e.g.
--   { "tab-group-7b96", "[vm/api]" } -> { id = "tab-group-7b96", title =
--   "[vm/api]", detail = "current" } for the one in front, else detail "".
local function rowsOf(windows)
  local rows = {}
  for i, window in ipairs(byRecency(windows)) do
    table.insert(rows, { id = window[1], title = window[2], detail = i == 1 and "current" or "" })
  end
  return rows
end

S = require("switcher").new({
  name = "ghostty_switcher",
  bundle = GHOSTTY,
  list = function(show)
    show(rowsOf(ask(LIST_WINDOWS, "listing Ghostty's windows")))
  end,
  activate = function(id)
    ask(ACTIVATE:format(id), "bringing window " .. id .. " forward")
  end,
})

-- Checked again at the end of the wait: `tell application` to a Ghostty that
-- quit meanwhile would launch it.
S.settled = hs.timer.delayed.new(SETTLE_SECONDS, function()
  S.guarded(function()
    if not hs.application.get(GHOSTTY) then
      return
    end
    local id = ask(FRONT_WINDOW, "reading Ghostty's front window")
    if id ~= "" then
      visit(id)
      S.log("focused %s", id)
    end
  end)
end)

-- Started at its first activation, not its launch: by then it answers
-- accessibility. It ends with the process, so a new Ghostty needs a new one.
local function watch(app)
  if S.focus then
    return
  end
  S.focus = app:newWatcher(function()
    S.settled:start()
  end)
  S.focus:start({ hs.uielement.watcher.focusedWindowChanged })
end

-- Kept in S so the watcher is not garbage-collected.
S.ghosttyWatcher = hs.application.watcher.new(function(_, eventType, app)
  if not app or app:bundleID() ~= GHOSTTY then
    return
  end
  if eventType == hs.application.watcher.activated then
    watch(app)
  elseif eventType == hs.application.watcher.terminated then
    S.settled:stop()
    -- None if it launched and quit without ever being activated.
    if S.focus then
      S.focus:stop()
      S.focus = nil
    end
    recent = {}
  end
end)
S.ghosttyWatcher:start()

-- Apply on load in case Ghostty already runs.
local running = hs.application.get(GHOSTTY)
if running then
  watch(running)
end

return S
