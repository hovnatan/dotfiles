-- iTerm2's window picker on a middle click (switcher.lua), its windows from
-- iterm2_api.py:
--
--   up: iterm2_api.listWindows --"list"--> iterm2_api.py
--        | "windows" event, within REPLY_SECONDS, else alerted
--        v
--   a row per window, the most recently focused first
--        | picked
--        v
--   iterm2_api.activateWindow --"window <id>"--> iterm2_api.py
--
-- The order is the focus history iterm2_api.py keeps since it started; a
-- window not focused since then sorts after, oldest opened first. The list
-- takes about 10 ms (2026-10-20), a click holds the button longer.
--
-- Why the Python API, not AppleScript or hs.window: the windows run full
-- screen, each in a Space of its own, which Hammerspoon cannot list (it
-- sees the current Space's), and AppleScript took 1.3s for 5 windows and
-- their tabs, a round trip per property (2026-10-20). iterm2_api.py holds
-- the layout already.
local api = require("iterm2_api")

-- A reply later than this is alerted and dropped (iterm2_api.lua): a stuck
-- iterm2_api.py would otherwise pop the picker up long after the click,
-- over whatever is in front by then.
local REPLY_SECONDS = 1

-- A row per window, e.g.
--   { id = "<id>", title = "~/.dotfiles", detail = "3 tabs (current)" }
-- A window with no title of its own is named by its number, "window 6",
-- iTerm2's own (Cmd-Opt-6): its row changes with the order, its number not.
local function rowsOf(event)
  local rows = {}
  for _, window in ipairs(event.windows) do
    table.insert(rows, {
      id = window.window,
      title = window.title ~= "" and window.title or ("window " .. window.number),
      detail = string.format(
        "%d tab%s%s",
        window.tabs,
        window.tabs == 1 and "" or "s",
        window.window == event.current and " (current)" or ""
      ),
    })
  end
  return rows
end

local S
S = require("switcher").new({
  name = "iterm2_switcher",
  bundle = "com.googlecode.iterm2",
  list = function(show)
    api.listWindows(REPLY_SECONDS, function(event)
      S.guarded(function()
        show(rowsOf(event))
      end)
    end)
  end,
  activate = api.activateWindow,
})

return S
