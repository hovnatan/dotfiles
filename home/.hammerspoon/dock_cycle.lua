-- A click on the Dock icon of the app in front walks that app's windows, the
-- most recently used first (AltTab's order, alttab.lua). macOS's own click
-- walks them in the order of their Spaces, which "Automatically rearrange
-- Spaces" keeps shuffling, so with a few fullscreen windows the next one is
-- anyone's guess.
--
-- No click is looked at unless the pointer is on that icon. The Dock says
-- which icon the pointer is on, and the tap on the left button runs only
-- while it is the front app's:
--
--   Dock --AXSelectedChildrenChanged--> update() <--activated-- app watcher
--                                          |
--          the icon the Dock has selected is the front app's,
--          and the pointer has not left the Dock?
--            yes: tap started          no: tap stopped
--
--   left button, no modifiers held, the tap running
--     down: pointer off the icon?  yes --> tap stopped, click unchanged
--           a walk under way, or AltTab lists two windows or more of the app?
--             no  --> unchanged: the Dock's own click
--             yes --> swallowed, as its up will be
--     up:   the walk's next window comes forward (AltTab)
--
-- A walk is the order as it was at its first click, so that each click goes
-- one window further back, where asking again would flip between two:
--
--   order A (in front), B, C, D
--   click -> B    click -> C    click -> D    click -> A
--
-- It ends when the pointer leaves the icon, or after WALK_IDLE seconds
-- without a click. The next click then starts from AltTab's order of that
-- moment, in which every window landed on counts as used: after A -> B -> C
-- the order is C, B, A, D, and one click goes to B. That is the one history,
-- the same Cmd-` shows; none is kept here.
--
-- What the Dock no longer gets on the front app's icon, when that app has
-- two windows or more: the plain click (macOS's own walk), and with it the
-- press-and-hold menu and the drag. A click with a modifier held goes
-- through, so Control-click still opens the menu.
local DOCK = "com.apple.dock"
local HOVER = "AXSelectedChildrenChanged"
local TYPES = hs.eventtap.event.types

-- A walk left alone this long is over: the pointer parked on the icon while
-- the keyboard was used, or left it with the Dock hidden, which the Dock
-- does not tell.
local WALK_IDLE = 5

-- Every arming and click is logged (event_log.lua), to the file only, e.g.
--   2026-11-18T16:02:11.410Z armed: pointer on Google Chrome's icon
--   2026-11-18T16:02:12.036Z walk: 7 windows of com.google.Chrome
--   2026-11-18T16:02:12.101Z click: window 2 of 7, id 12819
--   2026-11-18T16:02:15.870Z disarmed: pointer off the icon
local log, logDir = require("event_log").new("dock_cycle", { console = false })

-- fail() alerts and raises; guarded() runs what the Dock's notifications,
-- the tap and the timers call (whose errors go to the Console only) and
-- alerts what no fail() did (failure.lua).
local fail, guarded = require("failure").new("dock_cycle", log)
local altTab = require("alttab").new(fail)

-- S.observer, S.tap, S.watcher and S.focusTimer are kept so none is
-- collected; S.list is the Dock's list of icons, S.dockPid whose it is.
local S = { logDir = logDir }

-- The icon the tap is armed on; none while it is stopped.
local armedIcon

-- { bundle, ids, index, at, frame }: the app walked, its windows' ids in the
-- order at the first click, where in them the walk is, when its last click
-- was, and the icon's frame then.
local walk

-- Whether the button's down was swallowed, so its up is.
local pressed = false

-- An icon's frame is read live and moves with the Dock: up, Chrome's is
-- (848, 994, 65 x 81) on this 1080-high screen; hidden, its top is at 1085,
-- under the bottom edge, and in between while the Dock slides (2026-11-18).
-- The frames here assume a Dock at the bottom; update() says so of one on a
-- side.

-- Whether `point` is on the icon whose frame is `frame`: within its width,
-- and from its top down to the screen's edge, as far as the Dock takes a
-- click (5 points below the frame here). Never on a hidden Dock's.
local function onIcon(frame, point)
  return point.x >= frame.x and point.x <= frame.x + frame.w and point.y >= frame.y
end

-- Whether the Dock is up: the icon wholly on the screen the pointer is on.
local function dockUp(frame)
  local screen = hs.mouse.getCurrentScreen():fullFrame()
  return frame.y + frame.h <= screen.y + screen.h
end

local function endWalk(why)
  if walk then
    log("walk over: %s", why)
    walk = nil
  end
end

local function disarm(why)
  S.tap:stop()
  -- A button held across this: its up goes to the Dock, which makes nothing
  -- of an up without its down.
  pressed = false
  if armedIcon then
    log("disarmed: %s", why)
  end
  armedIcon = nil

  -- The Dock hiding under a pointer that stays put is no leaving: a walk
  -- goes on from where the pointer was at its last click.
  if walk and not onIcon(walk.frame, hs.mouse.absolutePosition()) then
    endWalk("pointer left the icon")
  end
end

-- The app icon the Dock has selected, i.e. the one under the pointer, or the
-- last one it was on: the Dock names it again as the pointer leaves, with
-- nothing to tell the two apart but where the pointer is (2026-11-18). None
-- once the Dock has been left a while. Folders, the Trash and separators
-- are other subroles.
local function selectedIcon()
  local icon = (S.list.AXSelectedChildren or {})[1]
  if icon and icon.AXSubrole == "AXApplicationDockItem" then
    return icon
  end
end

-- Start the tap if the pointer is on the front app's icon, else stop it.
local function update()
  local icon = selectedIcon()
  local front = hs.application.frontmostApplication()
  if not (icon and front and icon.AXURL.filePath == front:path()) then
    disarm("no icon of the front app under the pointer")
    return
  end
  local orientation = S.list.AXOrientation
  if orientation ~= "AXHorizontalOrientation" then
    fail("the Dock is on a side of the screen (" .. tostring(orientation) .. "); only one at the bottom is handled")
  end

  -- Left upward, the one way the Dock tells of. Only where the pointer is
  -- against the icon's top says so, and only of a Dock that is up: one still
  -- sliding in has its icon under the pointer, and sends no second
  -- notification once it is up, so that one arms. Not the icon's width: the
  -- notification comes as the pointer crosses its side, and the pointer read
  -- here can be a point short of it.
  local frame = icon.AXFrame
  if dockUp(frame) and hs.mouse.absolutePosition().y < frame.y then
    disarm("pointer off the icon")
    return
  end

  if not armedIcon then
    log("armed: pointer on %s's icon", front:name())
  end
  armedIcon = icon
  S.tap:start()
end

-- The ids of the windows a walk of `bundle` goes through, the one in front
-- first. Not the minimized: a walk shows windows, it does not restore them,
-- and each has its own tile in the Dock.
local function idsToWalk(bundle)
  local ids = {}
  for _, window in ipairs(altTab.windows(bundle)) do
    if not window.isMinimized then
      table.insert(ids, window.id)
    end
  end
  return ids
end

-- Whether to swallow the down: true once a walk is under way or begun.
local function onDown(event)
  if next(event:getFlags()) ~= nil then
    return false
  end

  -- The pointer left the Dock without the Dock saying so (it does not, once
  -- hidden, or past the end of its row): this click is for whatever is under
  -- it, and no later one comes here. No frame: the icon is gone, its app
  -- having quit.
  local frame = armedIcon.AXFrame
  if not (frame and onIcon(frame, event:location())) then
    disarm("click off the icon")
    return false
  end

  local bundle = hs.application.frontmostApplication():bundleID()
  local now = hs.timer.secondsSinceEpoch()
  if walk and walk.bundle ~= bundle then
    endWalk("another app in front")
  elseif walk and now - walk.at > WALK_IDLE then
    endWalk(string.format("%.0f s without a click", now - walk.at))
  end

  if not walk then
    local ids = idsToWalk(bundle)
    if #ids < 2 then
      log("%d of %s's windows to walk, two needed: click left to the Dock", #ids, bundle)
      return false
    end
    walk = { bundle = bundle, ids = ids, index = 1 }
    log("walk: %d windows of %s", #ids, bundle)
  end
  walk.at, walk.frame = now, frame
  return true
end

-- The up of a swallowed down: one window further, the last going round to
-- the first.
local function onUp()
  walk.index = walk.index % #walk.ids + 1
  local id = walk.ids[walk.index]
  log("click: window %d of %d, id %d", walk.index, #walk.ids, id)

  -- After the tap returns: the click is already swallowed, and AltTab's call
  -- would hold the tap. A window closed since the first click fails here,
  -- and the next click starts over from what there is.
  S.focusTimer = hs.timer.doAfter(0, function()
    if not guarded(altTab.focus, id) then
      endWalk("a window could not be brought forward")
    end
  end)
end

-- An error in here is alerted and the event goes on to the Dock, as if this
-- were not installed.
local function onLeftMouse(event)
  local swallow = false
  guarded(function()
    if event:getType() == TYPES.leftMouseDown then
      pressed = onDown(event)
      swallow = pressed
    elseif pressed then
      pressed = false
      onUp()
      swallow = true
    end
  end)
  return swallow
end

-- Watch the Dock running now for the icon under the pointer.
local function attach(dock)
  local list
  for _, child in ipairs(hs.axuielement.applicationElement(dock).AXChildren or {}) do
    if child.AXRole == "AXList" then
      list = child
    end
  end
  if not list then
    fail("the Dock (pid " .. dock:pid() .. ") shows no list of icons to accessibility")
  end

  if S.observer then
    S.observer:stop()
  end
  S.dockPid, S.list = dock:pid(), list
  S.observer = hs.axuielement.observer.new(S.dockPid)
  S.observer:callback(function()
    guarded(update)
  end)
  S.observer:addWatcher(list, HOVER)
  S.observer:start()
  log("watching the Dock (pid %d)", S.dockPid)
end

-- A Dock restarted (`killall Dock`, a crash) is another process, which the
-- observer of the old one hears nothing from. Looked for at each app
-- switch, so the walk is back at the first one after the restart. None
-- running is the moment in between: the next switch looks again.
local function followDock()
  local dock = hs.application.applicationsForBundleID(DOCK)[1]
  if not dock then
    log("the Dock is not running; looking again at the next app switch")
  elseif dock:pid() ~= S.dockPid then
    attach(dock)
  end
end

S.tap = hs.eventtap.new({ TYPES.leftMouseDown, TYPES.leftMouseUp }, onLeftMouse)

local dock = hs.application.applicationsForBundleID(DOCK)[1]
if not dock then
  fail("the Dock is not running")
end
attach(dock)

S.watcher = hs.application.watcher.new(function(_, eventType)
  if eventType == hs.application.watcher.activated then
    guarded(function()
      followDock()
      update()
    end)
  end
end)
S.watcher:start()

-- Apply on load in case the pointer is already on the icon.
update()

return S
