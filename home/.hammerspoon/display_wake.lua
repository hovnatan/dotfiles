-- Which apps are asking macOS to keep the display awake. A video player
-- does for as long as its video plays, and a call or a slide show likewise,
-- so a holder means eyes are on the screen even with no input for minutes.
-- eye_breaks.lua asks before it takes idle time as time away.
--
--   pmset -g assertions            M.parse                   M.first
--   "... pid 70176(Google    -->   { app = "Google     -->   that holder, or
--    Chrome): [0x..] 00:00:05        Chrome", kind =         nil when every
--    NoDisplaySleepAssertion         "NoDisplaySleep-        holder is in
--    named: "Video Wake Lock""       Assertion", name =      IGNORED
--                                    "Video Wake Lock" }
--
-- Chrome's "Video Wake Lock" was seen on 2026-11-17 while its video played;
-- its "Playing audio" is a NoIdleSleepAssertion, about system sleep, and
-- is not counted: listening is not looking.
--
-- M.parse and M.first make no Hammerspoon calls, so
-- scripts/tests/eye_breaks_test.lua runs them on saved pmset output.
local M = {}

-- The assertion types that keep the display on for a user-facing reason.
-- Not InternalPreventDisplaySleep: powerd holds that one for its own
-- display-off delay.
local DISPLAY_KINDS = { PreventUserIdleDisplaySleep = true, NoDisplaySleepAssertion = true }

-- Apps whose hold says nothing about anyone watching, each with why. A
-- holder not listed here stops idle time from counting as rest, so an app
-- that holds for no reason shows as never resting while idle: the menu
-- names it, and it belongs in this table.
local IGNORED = {
  WhatsApp = 'holds "net.whatsapp.idletimer" for as long as it runs, video or not (18 h on 2026-11-17)',
  caffeinate = "keeps the display on for an unattended job, not for a viewer",
}

-- Every display holder in `text`, the output of `pmset -g assertions`, in
-- its order. Raises on text that is not that output, or a display line it
-- cannot read: an empty list there would say "nobody is watching".
function M.parse(text)
  local listing = text:match("\nListed by owning process:\n(.*)")
  if not listing then
    error('display_wake: no "Listed by owning process:" section in the pmset output; its format changed')
  end
  -- The kernel's own assertions follow, in another format.
  listing = listing:match("^(.-)\nKernel Assertions:") or listing

  local holders = {}
  for line in listing:gmatch("[^\n]+") do
    -- "   pid 70176(Google Chrome): [0x000a11c000058b0a] 00:00:05 NoDisplaySleepAssertion named: "Video Wake Lock"  "
    -- The app name may hold parentheses ("Google Chrome Helper (Renderer)").
    local app, kind, name = line:match('^%s+pid %d+%((.-)%): %[0x%x+%] [%d:]+ (%S+) named: "(.*)"')
    if app and DISPLAY_KINDS[kind] then
      table.insert(holders, { app = app, kind = kind, name = name })
    elseif not app and line:match("^%s+pid %d") then
      for display in pairs(DISPLAY_KINDS) do
        if line:find(display, 1, true) then
          error("display_wake: cannot read this pmset line; its format changed: " .. line)
        end
      end
    end
  end
  return holders
end

-- The first holder that is not ignored, or nil.
function M.first(holders)
  for _, holder in ipairs(holders) do
    if not IGNORED[holder.app] then
      return holder
    end
  end
  return nil
end

-- The app (and its reason) keeping the display awake now, or nil.
function M.watching()
  local out, ok, _, code = hs.execute("/usr/bin/pmset -g assertions")
  if not ok then
    error(string.format("display_wake: pmset -g assertions failed (exit %s): %s", tostring(code), tostring(out)))
  end
  return M.first(M.parse(out))
end

return M
