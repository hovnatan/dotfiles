-- Ghostty's window picker on a middle click (switcher.lua), its windows from
-- AltTab (alttab.lua):
--
--   up: AltTab's windows of Ghostty, the most recently focused first
--        v
--   a row per Ghostty window
--        | picked
--        v
--   AltTab brings it to front, switching to its Space
--
-- Why AltTab, not Ghostty's AppleScript: Ghostty's order is no history, from A
-- to C across fullscreen Spaces it read C, w1, w2, A (2026-11-04), so the window
-- left was never second, and the history kept here to make up for it lasted
-- only as long as Hammerspoon. AltTab keeps it already, across reloads. And
-- `tell application "Ghostty"` reaches one instance: a second one started for a
-- test hid every window of the first (2026-11-06). AltTab lists both.
-- A window's title carries Ghostty's bell mark, which here says which window
-- rang.
local GHOSTTY = "com.mitchellh.ghostty"

-- S.fail is the switcher's, made below: what AltTab gets wrong is alerted
-- under this module's name.
local S
local altTab = require("alttab").new(function(msg)
  S.fail(msg)
end)

-- Ghostty's windows, the most recently focused first. Being clicked, Ghostty
-- has at least one, so none means AltTab lost track.
local function ghosttyWindows()
  local windows = altTab.windows(GHOSTTY)
  if #windows == 0 then
    S.fail("AltTab lists no Ghostty window; check it has not excluded Ghostty")
  end
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
    altTab.focus(id)
  end,
})

return S
