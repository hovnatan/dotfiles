-- Ghostty's window picker on a middle click (switcher.lua), its windows from
-- AltTab's command line, which asks the AltTab running:
--
--   up: AltTab --detailed-list --> every app's windows, as JSON
--        v
--   a row per Ghostty window, the most recently focused first
--        | picked
--        v
--   AltTab --focus=<id>: to front, switching to its Space
--
-- Why AltTab, not Ghostty's AppleScript: Ghostty's order is no history, from A
-- to C across fullscreen Spaces it read C, w1, w2, A (2026-11-04), so the window
-- left was never second, and the history kept here to make up for it lasted
-- only as long as Hammerspoon. AltTab keeps it already, across reloads. And
-- `tell application "Ghostty"` reaches one instance: a second one started for a
-- test hid every window of the first (2026-11-06). AltTab lists both.
-- Not hs.window, which sees only the current Space's windows.
--
-- Both calls run in Hammerspoon's process and hold its one thread, 11 ms and
-- 12 ms (2026-11-06), the CLI's own 2 s each way bounding a hung AltTab.
-- In-process, a failure raises where the picker can give the keyboard back; an
-- hs.task's would come too late. A window's title carries Ghostty's bell mark,
-- which here says which window rang.
local GHOSTTY = "com.mitchellh.ghostty"
local ALTTAB = "/Applications/AltTab.app/Contents/MacOS/AltTab"

local S

-- Run AltTab with `args`: what it printed, else alerted and raised, naming
-- `what`. AltTab says why on stderr, e.g. that it is not running, or that a
-- window closed since the list; the shell, if AltTab is not installed.
local function altTab(args, what)
  local out, _, _, rc = hs.execute(ALTTAB .. " " .. args .. " 2>&1")
  if rc ~= 0 then
    S.fail(string.format("%s failed (exit %s): %s", what, tostring(rc), out:match("^(.-)%s*$")))
  end
  return out
end

-- Ghostty's windows as AltTab has them, the most recently focused first. The
-- list is every app's, in no such order: lastFocusOrder 0 is the window in
-- front of all, and Ghostty's numbers have gaps for the other apps' windows.
-- Being clicked, Ghostty has at least one, so none means AltTab lost track.
local function ghosttyWindows()
  local out = altTab("--detailed-list", "listing windows")
  local ok, reply = pcall(hs.json.decode, out)
  if not ok or type(reply) ~= "table" or type(reply.windows) ~= "table" then
    S.fail(string.format("AltTab's window list is not as expected: %q", out:match("^(.-)%s*$"):sub(1, 80)))
  end

  local windows = {}
  for _, window in ipairs(reply.windows) do
    if window.appBundleId == GHOSTTY then
      table.insert(windows, window)
    end
  end
  if #windows == 0 then
    S.fail("AltTab lists no Ghostty window; check it has not excluded Ghostty")
  end
  table.sort(windows, function(a, b)
    return a.lastFocusOrder < b.lastFocusOrder
  end)
  return windows
end

-- A row per window, e.g.
--   { id = 19321, title = "[vm/api]", ... } -> { id = "19321", title =
--   "[vm/api]", detail = "current" } for the one in front, else detail "".
-- The id a string, as the other switchers': it goes to the page and back.
local function rowsOf(windows)
  local rows = {}
  for i, window in ipairs(windows) do
    table.insert(rows, {
      id = string.format("%d", window.id),
      title = window.title,
      detail = i == 1 and "current" or "",
    })
  end
  return rows
end

S = require("switcher").new({
  name = "ghostty_switcher",
  bundle = GHOSTTY,
  list = function(show)
    show(rowsOf(ghosttyWindows()))
  end,
  activate = function(id)
    altTab("--focus=" .. id, "bringing window " .. id .. " forward")
  end,
})

return S
