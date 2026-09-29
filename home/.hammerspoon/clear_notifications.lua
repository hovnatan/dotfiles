-- alt+0 dismisses every notification banner on screen. macOS has no
-- shortcut for it, and iTerm2's bell banners pile up while background tabs
-- keep ringing once its alert style is Persistent (System Settings >
-- Notifications > iTerm2, a manual per-machine step; see the bell note in
-- scripts/setup_user_symlinks.sh).
--
-- Banners are elements of the NotificationCenter process that accessibility
-- exposes with named actions, not buttons to click:
--   AXNotificationCenterAlert       one banner       -> "Close"
--   AXNotificationCenterAlertStack  grouped banners  -> "Clear All"
-- The action names come back as "Name:Close\nTarget:0x0\nSelector:(null)",
-- so they are matched on the "Name:" line. They are English here; another
-- system language (or a macOS release that renames them) makes the hotkey
-- report the banners it could not close instead of silently doing nothing.
local M = {}

local NC_BUNDLE_ID = "com.apple.notificationcenterui"
local ACTION = {
  AXNotificationCenterAlert = "Name:Close",
  AXNotificationCenterAlertStack = "Name:Clear All",
}
local MAX_PASSES = 3
local PASS_DELAY = 0.4 -- seconds for the closed banners to leave the tree

local function fail(msg)
  hs.alert.show("clear_notifications: " .. msg, 4)
  error("clear_notifications: " .. msg)
end

-- The Notification Center process that draws the banners. Not
-- hs.application.get(): see chrome.lua for why its miss path blocks
-- Hammerspoon. Also used by iterm2_bell_banners.lua, as is everything below.
function M.app()
  local app = hs.application.applicationsForBundleID(NC_BUNDLE_ID)[1]
  if not app then
    fail("NotificationCenter process not found")
  end
  return app
end

-- Every banner in Notification Center's windows, as { el, subrole, id, desc }
-- records, e.g. desc "iTerm2, Bell, Session fish:~ #2 just rang a bell!".
-- Only windows are walked: the process also owns the menu bar, whose tree
-- is large and has no notifications in it. A stack counts as one banner:
-- collapsed, its id and text are its newest notification's (desc then ends
-- in ", stacked"), and its older ones only appear, as single banners, once
-- it is expanded.
function M.banners()
  local found = {}
  local function walk(el)
    local subrole = el:attributeValue("AXSubrole")
    if ACTION[subrole] then
      table.insert(found, {
        el = el,
        subrole = subrole,
        id = el:attributeValue("AXIdentifier"),
        desc = el:attributeValue("AXDescription") or "",
      })
      return -- a stack's children are its texts, not further banners
    end
    for _, child in ipairs(el:attributeValue("AXChildren") or {}) do
      walk(child)
    end
  end
  for _, window in ipairs(hs.axuielement.applicationElement(M.app()):attributeValue("AXWindows") or {}) do
    walk(window)
  end
  return found
end

-- Close one banner, or clear a whole stack.
function M.press(banner)
  local wanted = ACTION[banner.subrole]
  for _, name in ipairs(banner.el:actionNames() or {}) do
    if name:find(wanted, 1, true) then
      banner.el:performAction(name)
      return
    end
  end
  fail("no " .. wanted .. " action on " .. banner.subrole .. ": " .. banner.desc)
end

-- One pass presses every banner's action; the next pass, after the tree has
-- settled, catches banners that were queued behind the ones just closed.
-- Banners still there after MAX_PASSES mean the actions stopped working.
local function pass(n)
  local found = M.banners()
  if #found == 0 then
    return
  end
  if n > MAX_PASSES then
    local descs = {}
    for _, banner in ipairs(found) do
      table.insert(descs, banner.desc)
    end
    fail(#found .. " banner(s) left after " .. MAX_PASSES .. " passes: " .. table.concat(descs, "; "))
  end
  for _, banner in ipairs(found) do
    M.press(banner)
  end
  M.timer = hs.timer.doAfter(PASS_DELAY, function()
    pass(n + 1)
  end)
end

-- A second press while passes are still pending restarts them rather than
-- running two chains that press the same banners twice.
function M.clearAll()
  if M.timer then
    M.timer:stop()
  end
  pass(1)
end

hs.hotkey.bind({ "alt" }, "0", M.clearAll)

return M
