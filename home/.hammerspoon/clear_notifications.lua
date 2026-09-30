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

-- The pid of the Notification Center process that draws the banners, or
-- nil while none runs (launchd starts it again on demand after it quits).
-- Cached while its accessibility element still answers as Notification
-- Center (0.2ms; a dead pid has no element at all, and the title check
-- catches a pid reused after a restart). Only then is it looked up by
-- bundle id: hs.application's lookup has returned nothing for the running
-- process during a burst of hs CLI calls, so it stays off the common path;
-- not hs.application.get() either, see chrome.lua for why its miss path
-- blocks Hammerspoon. Also used by iterm2_bell_banners.lua, as is
-- everything below.
local NC_TITLE = "Notification Center"
local cachedPid

function M.pid()
  local el = cachedPid and hs.axuielement.applicationElementForPID(cachedPid)
  if el and el:attributeValue("AXTitle") == NC_TITLE then
    return cachedPid
  end
  local app = hs.application.applicationsForBundleID(NC_BUNDLE_ID)[1]
  cachedPid = app and app:pid()
  return cachedPid
end

-- Its accessibility element, where banners are about to be read and a
-- missing process is a broken setup.
function M.element()
  local pid = M.pid()
  if not pid then
    fail("NotificationCenter process not found")
  end
  return hs.axuielement.applicationElementForPID(pid)
end

-- A window's or element's list attribute, raised when the read fails.
-- attributeValue reports a failed read (a dead pid, missing Accessibility
-- permission, an unsupported attribute) as nil plus a message, e.g.
--   nil, "Attribute is not supported by target"
-- and an attribute that has no value (kAXErrorNoValue) as a plain nil. With
-- nothing there the list is normally an empty table (checked on macOS 27: a
-- windowless process's AXWindows, a leaf's AXChildren), so the plain nil is
-- an empty list too. Only the message is a failure: a caller that took a
-- failed read for an empty list would act on a screen it never saw, and the
-- bell module used to drop its banners that way.
local function list(el, attribute, what)
  local value, err = el:attributeValue(attribute)
  if err ~= nil then
    fail(
      "Notification Center's "
        .. what
        .. " could not be read ("
        .. tostring(err)
        .. "); is Hammerspoon allowed in System Settings > Privacy & Security > Accessibility?"
    )
  end
  return value or {}
end

-- Every banner in Notification Center's windows, as { el, subrole, id, desc }
-- records, e.g. desc "iTerm2, Bell, Session fish:~ #2 just rang a bell!".
-- Only windows are walked: the process also owns the menu bar, whose tree
-- is large and has no notifications in it. A stack counts as one banner:
-- collapsed, its id and text are its newest notification's (desc then ends
-- in ", stacked"), and its older ones only appear, as single banners, once
-- it is expanded. Returns the screen, or raises: never an empty list for a
-- read that failed.
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
    for _, child in ipairs(list(el, "AXChildren", "child list")) do
      walk(child)
    end
  end
  for _, window in ipairs(list(M.element(), "AXWindows", "window list")) do
    walk(window)
  end
  return found
end

-- Close one banner, or clear a whole stack.
function M.press(banner)
  local wanted = ACTION[banner.subrole]
  local names, err = banner.el:actionNames()
  if names == nil then
    fail("actions of " .. banner.subrole .. " could not be read (" .. tostring(err) .. "): " .. banner.desc)
  end
  for _, name in ipairs(names) do
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

-- Called once the first pass has pressed every banner on screen: the one
-- bulk dismissal there is, so a module tracking banners
-- (iterm2_bell_banners.lua) can forget them all without a scan of its own.
-- After the pass, not before: a pass that raises (a failed read, a banner
-- without its action) leaves banners on screen, and a tracker told
-- beforehand would have forgotten them for good.
M.listeners = {}

function M.onClearAll(fn)
  table.insert(M.listeners, fn)
end

-- A second press while passes are still pending restarts them rather than
-- running two chains that press the same banners twice.
function M.clearAll()
  if M.timer then
    M.timer:stop()
  end
  pass(1)
  for _, fn in ipairs(M.listeners) do
    fn()
  end
end

hs.hotkey.bind({ "alt" }, "0", M.clearAll)

return M
