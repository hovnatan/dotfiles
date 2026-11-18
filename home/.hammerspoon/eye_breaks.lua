-- Eye breaks: a menu-bar clock that counts down to the next break, a tab on
-- the screen's right edge (the badge) while a break is due, and a break
-- screen when the badge is clicked; no break comes up by itself. A short
-- break, 30 seconds, is due 20 minutes after the last rest; a long one, 10
-- minutes, after 75 minutes without a rest of that length. A right click
-- on the badge snoozes the due break for 10 minutes; the menu has that
-- too, and a snooze of 30.
--
--   nothing due       menu bar  3m        plain: a break is due in 3 min
--   short break due   menu bar (+29m)     on red: it is 29 min overdue
--                     badge    (+29m|     the same number, on red
--   long break due    both      +2m       on purple
--
-- The clock is coloured badge or no badge; the times since each rest are
-- in the menu. The badge stays down while an app keeps the display awake
-- (a playing video): the break is as due, but not in the way. It still
-- comes up for 5 seconds every 15 minutes, so that a film does not bury
-- it. The timing and its settings are eye_breaks_core.lua (the state
-- machine is drawn there); this file is its senses and its drawing:
--
--   hs.timer, every 30 s (1 s during a break,  +
--   or a glimpse of the badge), and each lock  |
--   and unlock as it happens ------------------+
--   hs.host.idleTime, lock watcher, -----------+--> core.tick --> events --> log, sound,
--                                              |                             phone (ntfy)
--   display_wake (is a video keeping the       |
--   display awake? then idle is not away,      |
--   and the badge stays down)                  |
--                                              |
--   badge click, menu clicks, the break -------+--> core.dueBreakNow / skip /
--   screen's Skip button, Esc; a right         |    snooze / setBadge / ...
--   click on the badge                         |
--   (its Lock button locks the screen)         |
--                                              |
--                                              v
--                    core.view  --> menu-bar title, badge, break screen
--                    core.saved --> hs.settings "eye_breaks.state"
--
-- The menu-bar item has the two breaks and the badge's switch, which is
-- saved, so it outlives a reload. From a shell:
--   hs -q -c 'require("eye_breaks").breakNow()'
-- also longBreakNow(), dueBreakNow() (the badge's click), skip(), lock(),
-- snooze() (a right click on the badge), longSnooze().
-- Keep the -q. Without it Hammerspoon echoes every console line to the
-- connected `hs`, and one that was killed stays registered: print() then
-- raises in whatever module logs next, until a reload (seen 2026-11-17).
local log = require("event_log").new("eye_breaks")
local fail, guarded = require("failure").new("eye_breaks", log)
local core = require("eye_breaks_core")
local displayWake = require("display_wake")
local ntfy = require("ntfy")

local M = {}

local cfg = core.defaults
local SETTINGS_KEY = "eye_breaks.state"
-- Seconds between ticks. Nothing shown is finer than a minute, and a lock
-- or unlock ticks at once (below), so the regular tick can be slow; the
-- break screen counts down by the second, and the badge's 5 s glimpse over
-- a video ends by it.
local TICK, BREAK_TICK = 30, 1
local RETURN_SOUND, RETURN_VOLUME = "Glass", 0.3

-- The badge: a tab on the screen's right edge, BADGE_AT of the way down
-- it, up while a break is due. Its colour is the break a click on it
-- brings: red a short one, purple a long one.
--
--        screen edge |
--        +-----------|
--       (    +29m    |   the menu-bar clock's text: the due break is 29
--        +-----------|   minutes overdue
-- No words on it, by request; BADGE_W fits "+1h02m" at BADGE_TEXT, and
-- padding. Corners are rounded on the left only.
local BADGE_W, BADGE_H, BADGE_RADIUS, BADGE_TEXT, BADGE_AT = 58, 28, 8, 12, 0.5
-- The due break's colour, under white text: the badge's fill, and the
-- menu-bar clock's (below).
local DUE_COLOR = {
  short = { red = 0.8, green = 0.15, blue = 0.15, alpha = 0.9 },
  long = { red = 0.45, green = 0.2, blue = 0.75, alpha = 0.9 },
}
local function dueColor(due)
  return DUE_COLOR[due] or fail("no colour for a break called " .. tostring(due))
end
-- Above other apps' windows, on every Space, and over full-screen apps.
local ON_TOP = { "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" }

-- The two canvas elements everything here is drawn from: a filled
-- rectangle (rounded by `radius`, if given; the whole canvas with no
-- `frame`) and a line of centred text in a grey of `white`, 1 for white.
local function fill(color, radius, frame)
  return {
    type = "rectangle",
    action = "fill",
    fillColor = color,
    roundedRectRadii = radius and { xRadius = radius, yRadius = radius },
    frame = frame,
  }
end
local function centredText(str, size, white, frame)
  return {
    type = "text",
    text = str,
    textSize = size,
    textColor = { white = white },
    textAlignment = "center",
    frame = frame,
  }
end

-- Whole seconds, which is what the saved state holds.
local clock = os.time

-- --- state --------------------------------------------------------------------

local ok, state, restoreNote = pcall(core.new, cfg, hs.settings.get(SETTINGS_KEY), clock())
if not ok then
  fail(string.format("%s. Clear it with: hs -q -c 'hs.settings.clear(\"%s\")', then reload", state, SETTINGS_KEY))
end
log("%s", restoreNote)

-- One late tick must not pass for sleep, which the core takes as rest.
if cfg.asleepAfter < 3 * TICK then
  fail(string.format("asleepAfter (%d s) must be at least 3 ticks (%d s)", cfg.asleepAfter, 3 * TICK))
end

-- --- the badge ----------------------------------------------------------------

-- A tab on the right edge of the screen with the focused window. A click
-- on it starts the due break (so it takes the clicks on its own rectangle;
-- they do not reach the window, or the scroll bar, under it), without
-- taking focus.
local badge = hs.canvas.new({ x = 0, y = 0, w = BADGE_W, h = BADGE_H })
badge:level(hs.canvas.windowLevels.overlay)
badge:behavior(ON_TOP)
badge:clickActivating(false)
-- Wider than the canvas by the radius: the right corners fall outside it
-- and are cut off, which leaves that side square against the edge. The
-- colour and the text are drawBadge's, at each draw.
badge[1] = fill(DUE_COLOR.short, BADGE_RADIUS, { x = 0, y = 0, w = BADGE_W + BADGE_RADIUS, h = BADGE_H })
badge[2] = centredText("", BADGE_TEXT, 1, { x = 0, y = 6, w = BADGE_W, h = BADGE_H - 6 })
badge:canvasMouseEvents(true)
-- A click takes the due break. A ctrl-click, macOS's other way to
-- right-click, snoozes it as a right click does (below).
badge:mouseCallback(function(_, message)
  if message ~= "mouseDown" then
    return
  end
  if hs.eventtap.checkKeyboardModifiers().ctrl then
    M.snooze()
  else
    M.dueBreakNow()
  end
end)
M.badge = badge
local badgeShown = false

-- A right click on the badge snoozes the due break (by request), as the
-- menu's "Snooze this break" does. The canvas calls back "mouseDown" for
-- every button without saying which, and the buttons read at that moment
-- are up again after a quick click, so the right button is caught as its
-- own event, on a tap that runs only while the badge is up (listenFor-
-- RightClicks, from drawBadge):
--
--   right button down, on the badge  --> swallowed; snooze
--   right button up after it         --> swallowed too, so that nothing
--                                        under the badge gets half a click
--   any other right click            --> passed on untouched
local TYPES = hs.eventtap.event.types
local swallowUp = false
local rightTap = hs.eventtap.new({ TYPES.rightMouseDown, TYPES.rightMouseUp }, function(event)
  if event:getType() == TYPES.rightMouseUp then
    local mine = swallowUp
    swallowUp = false
    return mine
  end
  local at, f = event:location(), badge:frame()
  if not (badgeShown and at.x >= f.x and at.x < f.x + f.w and at.y >= f.y and at.y < f.y + f.h) then
    return false
  end
  swallowUp = true
  -- Once the tap has answered: macOS switches off a tap that is slow to,
  -- and snoozing is a whole step.
  M.snoozing = hs.timer.doAfter(0, M.snooze)
  return true
end)
M.rightTap = rightTap

-- The tap on or off, with the badge. macOS can switch a tap off by itself
-- (one that was slow to answer); the next draw of the badge finds that
-- here and starts it again, with a line in the log.
local listening = false
local function listenForRightClicks(on)
  if rightTap:isEnabled() == on then
    listening = on
    return
  end
  if not on then
    rightTap:stop()
    listening = false
    return
  end
  if listening then
    log("macOS had switched off the tap for right clicks on the badge: starting it again")
  end
  rightTap:start()
  if not rightTap:isEnabled() then
    fail("could not start the event tap for right clicks on the badge: does Hammerspoon have Accessibility access?")
  end
  listening = true
end

-- The badge with `text` on it, in the colour of `due`; hidden with no text.
local function drawBadge(text, due)
  -- No screen at all (lid shut, displays asleep) has nowhere to draw.
  local screen = text and hs.screen.mainScreen()
  if not screen then
    if badgeShown then
      badge:hide()
      badgeShown = false
    end
    listenForRightClicks(false)
    return
  end

  badge[1].fillColor = dueColor(due)
  badge[2].text = text
  local f = screen:frame()
  badge:topLeft({ x = f.x + f.w - BADGE_W, y = f.y + math.floor((f.h - BADGE_H) * BADGE_AT) })
  if not badgeShown then
    badge:show()
    badgeShown = true
  end
  listenForRightClicks(true)
end

-- --- the break screen ---------------------------------------------------------

-- One canvas per screen while a break is up, and Esc bound to skip. The
-- canvases take clicks (they have a mouse callback), so the apps under them
-- get none; the keyboard stays with the focused app.
--
-- A break screen left up by an error would cover every display with nothing
-- running to take it down, so: Esc is bound before any canvas shows, each
-- canvas is recorded before the next is made, and closeOverlay() takes down
-- whatever part exists (the error paths below call it).
--
-- The display is not kept awake under it, by request (it was, for a day):
-- a long break outlasts the display's sleep timer, and the Mac should lock
-- with nobody at it, as it does when the display sleeps. So the countdown
-- goes dark part-way; the Lock button locks at once, and a break that ends
-- under the lock tells the phone (step, below), as nothing can draw over
-- the lock screen.
local overlays, overlayLong, escKey = nil, nil, nil
local COUNT = 4 -- index of the countdown element below

-- 30 -> "30s", 600 -> "10m": a break's length, for the menu and the screen.
local function span(seconds)
  return seconds < 60 and string.format("%ds", seconds) or core.fmt(seconds)
end

local function button(id, label, x, y)
  local w, h = 180, 40
  local box = fill({ white = 1, alpha = 0.15 }, 8, { x = x, y = y, w = w, h = h })
  local text = centredText(label, 17, 0.9, { x = x, y = y + 9, w = w, h = h - 9 })
  box.id, box.trackMouseDown = id, true
  text.id, text.trackMouseDown = id .. "_label", true
  return box, text
end

local function overlayFor(screen, long)
  local f = screen:fullFrame()
  local mid = f.h / 2
  local function text(str, size, white, y, h)
    return centredText(str, size, white, { x = 0, y = y, w = f.w, h = h })
  end

  local canvas = hs.canvas.new(f)
  canvas:level(hs.canvas.windowLevels.screenSaver)
  canvas:behavior(ON_TOP)
  canvas:clickActivating(false)
  canvas:appendElements(fill({ white = 0.05, alpha = 0.92 }))
  canvas:appendElements(text(long and "Long break" or "Look away", 64, 1, mid - 160, 84))
  canvas:appendElements(
    text(long and "Get up and walk off" or "Rest your eyes on something far off", 22, 0.75, mid - 60, 32)
  )
  canvas:appendElements(text("", 48, 1, mid, 64)) -- COUNT
  -- Two buttons, 180 wide and 20 apart, about the middle.
  canvas:appendElements(button("skip", "Skip (Esc)", f.w / 2 - 190, mid + 110))
  canvas:appendElements(button("lock", "Lock screen", f.w / 2 + 10, mid + 110))
  if long then
    local hint = string.format("Skipped after %s, it still counts as a short break", span(cfg.breakLength))
    canvas:appendElements(text(hint, 15, 0.55, mid + 170, 24))
  end
  canvas:appendElements(text("Locked, the break runs on, and its end is sent to the phone", 15, 0.55, mid + 196, 24))
  -- A button is two elements, "skip" and "skip_label"; a click on either.
  canvas:mouseCallback(function(_, message, id)
    local name = message == "mouseDown" and tostring(id):match("^%a+")
    if name == "skip" then
      M.skip()
    elseif name == "lock" then
      M.lock()
    end
  end)
  return canvas
end

local function closeOverlay()
  local canvases, key = overlays or {}, escKey
  overlays, overlayLong, escKey = nil, nil, nil
  for _, canvas in ipairs(canvases) do
    canvas:delete()
  end
  if key then
    key:delete()
  end
end

local function drawOverlay(o)
  if not o then
    closeOverlay()
    return
  end

  -- The other kind of break than the one on screen (a long one asked for
  -- from the shell under a short one): its screen is built anew.
  if overlays and overlayLong ~= o.long then
    closeOverlay()
  end
  if not overlays then
    escKey = hs.hotkey.bind({}, "escape", function()
      M.skip()
    end)
    overlays, overlayLong = {}, o.long
    for _, screen in ipairs(hs.screen.allScreens()) do
      table.insert(overlays, overlayFor(screen, o.long):show())
    end
  end
  -- "17" for the short break, "9:32" for the long one.
  local count = o.long and string.format("%d:%02d", o.remaining // 60, o.remaining % 60) or tostring(o.remaining)
  for _, canvas in ipairs(overlays) do
    canvas[COUNT].text = count
  end
end

-- --- drawing a view, and the timer ----------------------------------------------

local menu = hs.menubar.new(true, "eye_breaks") or fail("could not create the menu-bar item")
M.menu = menu

-- The menu-bar clock while a break is due: its text in white on a pill of
-- the due break's colour, as on the badge. A menu-bar title has no
-- background of its own to colour (styled text can only tint the box of
-- its glyphs, square and unpadded), so the pill is drawn as an image, in
-- the menu bar's own font, and shown as the item's icon in place of a title.
--
--    plain:  3m        due:  ( +29m )   <- PILL_H tall, PILL_PAD each side
local PILL_H, PILL_PAD, PILL_RADIUS = 18, 6, 5
local function pill(title, color)
  local text = hs.styledtext.new(title, {
    font = hs.styledtext.defaultFonts.menuBar,
    color = { white = 1 },
    paragraphStyle = { alignment = "center" },
  })
  local canvas = hs.canvas.new({ x = 0, y = 0, w = 1, h = PILL_H })
  local size = canvas:minimumTextSize(text)
  local w = math.ceil(size.w) + 2 * PILL_PAD
  canvas:size({ w = w, h = PILL_H })
  canvas[1] = fill(color, PILL_RADIUS)
  -- Half a point above the middle. The digits are 19 px tall in the 36 px
  -- of a 2x screen, which leaves 17: no exact middle, and the odd pixel
  -- goes below (8 px of red above, 9 below), where the short "m" does not
  -- add to it. Centred, it went above (seen in a screenshot of 2026-11-17).
  -- This is for the 13 pt menu-bar font in an 18 pt pill; another size of
  -- either wants another look.
  local y = (PILL_H - size.h) / 2 - 0.5
  canvas[2] = { type = "text", text = text, frame = { x = 0, y = y, w = w, h = size.h } }
  local image = canvas:imageFromCanvas()
  canvas:delete()
  return image
end

-- The menu-bar item's face: `title` plain, or on the pill of `due`'s colour.
-- Nothing is redrawn while both stay as they are: the title changes once a
-- minute, and a pill is an image to build.
local shownTitle, shownDue = nil, nil
local function showTitle(title, due)
  if title == shownTitle and due == shownDue then
    return
  end
  if due then
    menu:setTitle("")
    -- false: not a template image, which the menu bar would draw in one colour.
    menu:setIcon(pill(title, dueColor(due)), false)
  else
    menu:setIcon(nil)
    menu:setTitle(title)
  end
  shownTitle, shownDue = title, due
end

local stopped = false -- the timer gave up after an error; only a reload restarts it
local step -- below; the timer and render() name each other

-- One step, from the timer or the lock watcher. A step that raises would
-- raise again at every tick: stop, take down a break screen nothing would
-- now end, and say so in the menu bar, where the frozen clock would
-- otherwise look alive.
local function tick()
  if stopped then
    return
  end
  if not guarded(step) then
    M.timer:stop()
    stopped = true
    closeOverlay()
    showTitle("breaks: error", nil)
    log("timer stopped after the error above; reload Hammerspoon once it is fixed")
  end
end

-- The lock screen is away for certain, where idle time is only a guess.
-- It ticks as it happens, so a lock is timed to the second, not to the
-- 30 s tick it would fall between: the unlock ticks once still locked,
-- which is where a lock of a break's length is credited as rest.
--
--   12:00:07 lock    -> tick (locked): away since 12:00:07
--   12:00:42 unlock  -> tick (locked): 35 s >= 30 s, rest
--                    -> tick (unlocked): "returned"
--
-- At load the watcher has seen nothing yet, so macOS is asked: a reload
-- under the lock screen took it for unlocked, and asked display_wake what
-- was playing to nobody (2026-11-18).
local session = hs.caffeinate.sessionProperties()
  or fail("no session properties from macOS: cannot tell whether the screen is locked")
local locked = session.CGSSessionScreenIsLocked == true
if locked then
  log("loaded under a locked screen")
end
M.lockWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.screensDidLock then
    locked = true
    log("screen locked")
    tick()
  elseif event == hs.caffeinate.watcher.screensDidUnlock then
    tick()
    locked = false
    log("screen unlocked")
    tick()
  end
end)

-- One timer, restarted when the period changes (a break going up or down).
local ticking = nil -- its period
local function schedule(period)
  if ticking == period then
    return
  end
  if M.timer then
    M.timer:stop()
  end
  ticking = period
  M.timer = hs.timer.doEvery(period, tick)
end

-- The state, for the next load. A tick that moved nothing but the time
-- (core.sameButTick: lastTickAt, and a rest clock running on while away)
-- is written only once the written one is half a regular tick old: every
-- 30 s tick, and one in 15 of a break's 1 s ticks, not each (a write is
-- the whole preferences file), at the screen or away from it.
local written = nil
local function save()
  local saved = core.saved(state)
  if written and core.sameButTick(written, saved) and saved.lastTickAt - written.lastTickAt < TICK / 2 then
    return
  end
  hs.settings.set(SETTINGS_KEY, saved)
  written = saved
end

local function render()
  local v = core.view(state, clock())
  showTitle(v.title, v.due)
  drawBadge(v.badge and v.title, v.due)
  drawOverlay(v.overlay)
  save()
  schedule((v.overlay or v.glimpse) and BREAK_TICK or TICK)
  return v
end

local function playReturnSound()
  local sound = hs.sound.getByName(RETURN_SOUND) or fail("no system sound named " .. RETURN_SOUND)
  sound:volume(RETURN_VOLUME):play()
end

-- A break ended under the lock screen, where nothing shows it: the phone
-- is told. The answer comes later, and is only logged: a push that failed
-- has nobody at the screen to alert.
local function tellPhone(long)
  local length = span(long and cfg.longBreakLength or cfg.breakLength)
  ntfy.push("Eye break over", string.format("The %s break has ended.", length), function(sent, detail)
    log("phone: %s%s", sent and "" or "NOT told, ", detail)
  end)
end

-- The app keeping the display awake, for the core, which asks at every
-- tick of an idle stretch, and at every tick with the badge wanted: pmset
-- is run at most once in TICK seconds.
-- Regular ticks are that far apart anyway; this is for the 1 s ticks of a
-- break, and the extra ones of a lock. An answer that old is fine either
-- way round: a video cannot start without input, and one that just ended
-- only delays "away" by that much.
local watch = { at = nil, holder = nil }
local function watching()
  local now = clock()
  if not watch.at or now - watch.at >= TICK then
    watch.at, watch.holder = now, displayWake.watching()
  end
  return watch.holder and watch.holder.app
end

function step()
  local events = core.tick(state, { now = clock(), idle = hs.host.idleTime(), locked = locked, watching = watching })
  -- "both clocks": the long one too, after a rest of a long break's length.
  local function restarted(long)
    return long and "both clocks restarted" or "clock restarted"
  end
  for _, event in ipairs(events) do
    if event.kind == "break_done" then
      log("%s done: %s", event.long and "long break" or "break", restarted(event.long))
      if event.locked then
        tellPhone(event.long)
      end
    elseif event.kind == "returned" then
      log("back after %.0f s away: %s", event.away, restarted(event.longRest))
      if event.sound then
        playReturnSound()
      end
    elseif event.kind == "badge_hidden" then
      -- watch.holder is the answer the core just got, here and below.
      log('badge hidden: %s keeps the display awake (%s "%s")', event.app, watch.holder.kind, watch.holder.name)
    elseif event.kind == "badge_glimpse" then
      log("badge up for %s over %s: not shown for %s", span(cfg.glimpseLength), event.app, span(cfg.glimpseEvery))
    elseif event.kind == "badge_unhidden" then
      log("badge no longer hidden: %s let the display go, or no break is due", event.app)
    elseif event.kind == "watching" then
      log('idle but not away: %s keeps the display awake (%s "%s")', event.app, watch.holder.kind, watch.holder.name)
    elseif event.kind == "watching_ended" then
      log("%s no longer holds the clock (input, lock, or it let the display go)", event.app)
    else
      fail("unknown event from the core: " .. tostring(event.kind))
    end
  end
  render()
end

-- --- actions: the menu, the break screen's buttons, and the shell ---------------

-- A function that applies `change(now)` to the state, steps and logs it:
-- `what`, and after it the string `change` returns, if any, for what shows
-- only once it is done. A step, not only a redraw: whether the badge shows
-- hangs on what a tick sees (a video playing), and a break skipped under a
-- video would put it up until the next one. Step before log: the screen
-- should follow a click even if the log line cannot be written. With the
-- timer stopped nothing would end a break or move the clock, so an action
-- then only says so.
local function action(what, change)
  return function()
    if stopped then
      hs.alert.show("eye_breaks: stopped after an error; reload Hammerspoon", 4)
      return
    end
    local clean = guarded(function()
      local more = change(clock())
      step()
      log("%s%s", what, more or "")
    end)
    if not clean then
      closeOverlay()
    end
  end
end

M.breakNow = action("break asked for", function(now)
  core.breakNow(state, now)
end)
M.longBreakNow = action("long break asked for", function(now)
  core.longBreakNow(state, now)
end)
-- The badge's click.
M.dueBreakNow = action("break asked for", function(now)
  return core.dueBreakNow(state, now) and ": the long one, which was due"
end)
-- A long break up for a short one's length is a short rest, the core says.
M.skip = action("break skipped", function(now)
  return core.skip(state, now) and ", a long break up long enough for a short rest: clock restarted"
end)

-- The due break snoozed, with no screen, for the core's two lengths:
--   M.snooze       10 min: a right click on the badge, the menu
--   M.longSnooze   30 min: the menu
local function snoozing(long)
  return action("due break snoozed", function(now)
    local length = long and cfg.longSnoozeFor or cfg.snoozeFor
    local snoozed = core.snooze(state, now, long)
    return snoozed and string.format(": none is due for %s", span(length)) or ": none was due, nothing changed"
  end)
end
M.snooze = snoozing(false)
M.longSnooze = snoozing(true)

-- The break screen's Lock button: the lock watcher ticks when it has locked.
function M.lock()
  log("lock asked for")
  hs.caffeinate.lockScreen()
end

local function setBadge(on)
  return action(on and "badge on" or "badge off", function()
    core.setBadge(state, on)
  end)
end

-- Built at each click, so the lines and checkmarks are the state's of then;
-- and drawn at each click, so the menu bar's number is the one its first
-- lines explain (drawn at the last tick, it could be a minute behind them).
-- With the timer stopped the menu bar says so, and is left saying it.
-- Also M.menuItems, to read or click the menu from a shell:
--   hs -q -c 'return require("eye_breaks").menuItems()[3].title'
local function menuItems()
  local v = stopped and core.view(state, clock()) or render()
  local items = {
    -- "30s break: 29m overdue (last rest 44m ago)"
    -- "10m break: due in 10m (last 10m rest 1h05m ago)"
    {
      title = string.format("%s break: %s (last rest %s ago)", span(cfg.breakLength), v.shortWhen, core.fmt(v.since)),
      disabled = true,
    },
    {
      title = string.format(
        "%s break: %s (last %s rest %s ago)",
        span(cfg.longBreakLength),
        v.longWhen,
        span(cfg.longBreakLength),
        core.fmt(v.sinceLong)
      ),
      disabled = true,
    },
  }
  -- Says where the badge is, while a break is due and it is not on screen.
  -- "Badge hidden: Google Chrome keeps the display awake (up 5s every 15m)"
  if v.hiddenBy then
    table.insert(items, {
      title = string.format(
        "Badge hidden: %s keeps the display awake (up %s every %s)",
        v.hiddenBy,
        span(cfg.glimpseLength),
        span(cfg.glimpseEvery)
      ),
      disabled = true,
    })
  end
  -- Says why an idle stretch did not reset the clock. An app named here
  -- when no video was on screen belongs in display_wake.lua's IGNORED.
  if v.watched then
    local w = v.watched
    local times = os.date("%H:%M", w.from) .. "-" .. os.date("%H:%M", w.to)
    table.insert(items, {
      title = string.format("Idle %s was not rest: %s kept the display awake", times, w.app),
      disabled = true,
    })
  end
  for _, item in ipairs({
    { title = "-" },
    { title = "Take a " .. span(cfg.breakLength) .. " break now", fn = M.breakNow },
    { title = "Take a " .. span(cfg.longBreakLength) .. " break now", fn = M.longBreakNow },
    -- Always there, so the menu keeps its shape, and greyed out while no
    -- break is due (by request): "Snooze this break for 10m" and "... for
    -- 30m". With a snooze running the first says why the badge is down,
    -- whichever of the two it was: "Break snoozed, 9m left".
    {
      title = v.snoozed and string.format("Break snoozed, %s left", v.snoozed)
        or "Snooze this break for " .. span(cfg.snoozeFor),
      fn = M.snooze,
      disabled = not v.due,
    },
    {
      title = "Snooze this break for " .. span(cfg.longSnoozeFor),
      fn = M.longSnooze,
      disabled = not v.due,
    },
    { title = "-" },
    { title = "Show badge", checked = v.badgeOn, fn = setBadge(not v.badgeOn) },
  }) do
    table.insert(items, item)
  end
  return items
end
menu:setMenu(menuItems)
M.menuItems = menuItems

-- The timer first, which a step that raises stops (tick, above). Then the
-- first step, which draws: a step and not only a draw, so that a badge a
-- video hides is not up until the first tick. The lock watcher's ticks
-- stop the timer too, so it starts after.
schedule(TICK)
tick()
M.lockWatcher:start()

return M
