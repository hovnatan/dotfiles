-- AltTab's command line, for the modules that list an app's windows and bring
-- one forward (ghostty_switcher.lua, dock_cycle.lua). It asks the AltTab
-- running:
--
--   AltTab --detailed-list --> every app's windows, as JSON
--   AltTab --focus=<id>    --> that window to front, switching to its Space
--
-- Why AltTab: it keeps the order windows were last focused in, across
-- fullscreen Spaces and across Hammerspoon reloads, and it sees every
-- instance of an app. hs.window sees only the current Space's windows, and a
-- history kept here lasts only as long as Hammerspoon does.
--
-- Both calls run in Hammerspoon's process and hold its one thread, 11 ms and
-- 12 ms (2026-11-06), the CLI's own 2 s each way bounding a hung AltTab.
-- In-process, a failure raises where the caller can still act on it (the
-- picker gives the keyboard back, a click is handed to the Dock); an
-- hs.task's would come too late.
local M = {}

local ALTTAB = "/Applications/AltTab.app/Contents/MacOS/AltTab"

-- fail: the calling module's own (failure.lua), so what goes wrong here is
-- alerted and raised under that module's name.
function M.new(fail)
  local A = {}

  -- Run AltTab with `args`: what it printed, else alerted and raised, naming
  -- `what`. AltTab says why on stderr, e.g. that it is not running, or that a
  -- window closed since the list; the shell, if AltTab is not installed.
  local function run(args, what)
    local out, _, _, rc = hs.execute(ALTTAB .. " " .. args .. " 2>&1")
    if rc ~= 0 then
      fail(string.format("%s failed (exit %s): %s", what, tostring(rc), out:match("^(.-)%s*$")))
    end
    return out
  end

  -- The windows of the app `bundle` as AltTab has them, the most recently
  -- focused first, e.g. { { id = 19321, title = "[vm/api]", lastFocusOrder =
  -- 0, isMinimized = false, ... }, ... }; none if AltTab lists none of that
  -- app. The list is every app's, in no such order: lastFocusOrder 0 is the
  -- window in front of all, and one app's numbers have gaps for the others'.
  function A.windows(bundle)
    local out = run("--detailed-list", "listing windows")
    local ok, reply = pcall(hs.json.decode, out)
    if not ok or type(reply) ~= "table" or type(reply.windows) ~= "table" then
      fail(string.format("AltTab's window list is not as expected: %q", out:match("^(.-)%s*$"):sub(1, 80)))
    end

    local windows = {}
    for _, window in ipairs(reply.windows) do
      if window.appBundleId == bundle then
        table.insert(windows, window)
      end
    end
    table.sort(windows, function(a, b)
      return a.lastFocusOrder < b.lastFocusOrder
    end)
    return windows
  end

  -- Bring the window `id` (a number, or a string of one: 19321 or "19321")
  -- to front, switching to its Space. %d: the JSON's ids can come as floats,
  -- which `..` would write as "19321.0".
  function A.focus(id)
    local n = string.format("%d", id)
    run("--focus=" .. n, "bringing window " .. n .. " forward")
  end

  return A
end

return M
