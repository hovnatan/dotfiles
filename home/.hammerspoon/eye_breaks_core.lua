-- Eye-break timing: the state machine behind eye_breaks.lua. It makes no
-- Hammerspoon calls, so scripts/tests/eye_breaks_test.lua drives it with
-- plain Lua and a made-up clock.
--
-- Two clocks run side by side:
--
--   lastRestAt      the last moment the eyes really rested. Only a break
--                   that ran to its end, or time away, moves it, so the
--                   "+29m" overdue in the menu bar is honest: skipping a
--                   break does not reset it.
--   lastLongRestAt  the same for a rest of a long break's length (10 min): a
--                   long break that ran to its end, or that long away. A
--                   short break does not restart it.
--
-- A short break is due breakAfter (20 min) after the last rest, a long one
-- longBreakAfter (75 min) after the last long rest. The menu bar and the
-- badge show one number, the same in both: the time until the next break
-- is due, and once one is, how long it has been. (The badge had the time
-- worked and the time to the short break, and the menu bar the time since
-- a rest: three numbers for one question, so they went, by request.)
--
--   since a rest   since a 10 min rest   shown
--   17m            17m                   "3m"    plain: a short break in 3 min
--   49m            1h05m                 "+29m"  red: it is 29 min overdue
--   8m             1h17m                 "+2m"   purple: the long one is, 2 min
--
-- A break screen comes up only when asked for: a click on the badge, or the
-- menu. (Breaks that came up by themselves every 20 min, with a snooze and
-- pauses, were here and went, by request; so did a session clock that
-- restarted after 5 min away.) Breaks come in two lengths, and the one the
-- badge's click brings follows the long clock:
--
--   since a rest   since a 10 min rest  the break that comes
--   22m            45m                  short, 30 s
--   22m            1h17m                long, 10 min (longBreakAfter is 75 min)
--
-- A long break skipped after a short one's length was a short rest: 40 s
-- into the second row's break, skip leaves 0m and 1h18m, and the next break
-- is long again.
--
-- A due break can also be snoozed, without its screen ever coming up, for
-- one of two lengths (by request; this is not the snooze of the breaks
-- that came up by themselves, above):
--
--   snoozeFor, 10 min       a right click on the badge, the menu
--   longSnoozeFor, 30 min   the menu
--
-- No break is due for that long, so the badge goes down and the clock
-- counts down plain. That is no rest, and the rest clocks run on under it,
-- so the break comes back as overdue as it really is:
--
--   rested last at 0:00, snoozed at 25:00
--   24:59   "+4m"   red
--   25:00   "10m"   plain: nothing is due before 35:00
--   35:00   "+15m"  red again: 15 min overdue, not 0
--
--                  asked for (badge click, menu)
--     +---------+ ---------------------------------------> +----------+
--     | working |                                          | on break |
--     +---------+ <--------------------------------------- +----------+
--       |     ^     ran to its end -> rest (the clocks restart)
--       |     |     skip           -> no rest
--  away |     | input again ("returned")
--       v     |
--     +---------+
--     |  away   |  rest on every tick, once away for a break's length
--     +---------+  (a long rest once away for a long break's)
--
-- Away is: screen locked, or no input for awayAfter with nothing keeping
-- the display awake (a playing video is no input and all eyes), or no tick
-- for asleepAfter (the Mac slept). There are no office hours, by request:
-- the clocks run, and the badge follows them, on every day and at any hour.
--
-- An app keeping the display awake is someone watching (a video, a call).
-- That is no rest, so the clocks run on; but the badge stays down over it,
-- by request, and is back when the app lets the display go. The menu-bar
-- clock keeps its colour all the while. Down, the badge still comes up for
-- glimpseLength (5 s) whenever it has not shown for glimpseEvery (15 min),
-- also by request: a film should not bury a due break for its two hours.
--
--   a film from 20:00, the badge up until then; rested last at 0:00
--   20:00   down
--   35:00   up, "+20m", until 35:05
--   50:00   up, "+35m", until 50:05
--
-- A break that comes due under the film has not shown at all since the
-- rest before it, so its first glimpse is at that moment.
--
--   tick at     idle  locked   result (awayAfter 5 min; a break asked for at
--                              11:20:00)
--   11:20:30     30 s   no     break ends, the rest clock restarts ("break_done")
--   11:30:55    295 s   no     reading, as far as it can tell: clock runs on
--   11:31:00    300 s   no     away since 11:26:00: rest, no event yet
--   11:31:05     1 s    no     "returned" after 305 s
local M = {}

M.defaults = {
  breakLength = 30, -- how long the break screen stays up
  -- The short breaks let the eyes refocus; the long one is for getting up.
  -- This long without a rest of longBreakLength, the due break is long.
  longBreakLength = 10 * 60,
  longBreakAfter = 75 * 60,
  -- This long with no input is away from the screen. A guess: reading a
  -- page or watching a video is no input either, so it is long (it was
  -- 60 s, and a minute's reading reset the clock).
  awayAfter = 5 * 60,
  -- This long with no tick: the Mac slept, or Hammerspoon was not running.
  -- No guess, so much shorter; but several of eye_breaks.lua's 30 s ticks,
  -- so that a late one is not taken for sleep (it checks).
  asleepAfter = 2 * 60,
  returnSoundAfter = 5 * 60, -- back from at least this long away: a sound says the clock restarted
  -- A short break is due this long after the last rest: the badge comes up,
  -- and the menu-bar clock takes its colour.
  breakAfter = 20 * 60,
  -- The badge, down over a video: not up for glimpseEvery, it comes up for
  -- glimpseLength. Long enough to catch the eye, too short to be in the way.
  glimpseEvery = 15 * 60,
  glimpseLength = 5,
  -- A due break snoozed (M.snooze): no break is due for this long. The
  -- first is the badge's right click and the menu's, the second the menu's.
  snoozeFor = 10 * 60,
  longSnoozeFor = 30 * 60,
}

-- What survives a Hammerspoon reload (M.saved / M.new), and its type.
local SAVED = {
  lastRestAt = "number",
  lastLongRestAt = "number",
  lastTickAt = "number",
  badge = "boolean",
}

-- 1380 -> "23m", 3900 -> "1h05m"
function M.fmt(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then
    return string.format("%dm", minutes)
  end
  return string.format("%dh%02dm", minutes // 60, minutes % 60)
end

-- A break's due time, `seconds` ahead (or behind, when 0 or less), as the
-- menu bar shows it and as the menu says it. Ahead it is rounded up, so
-- that the last minute reads "1m" and not "0m"; behind, down.
--   241 -> "5m",        240 -> "4m",        0 -> "+0m",        -1740 -> "+29m"
--   241 -> "due in 5m", 240 -> "due in 4m", 0 -> "0m overdue", -1740 -> "29m overdue"
local function countdown(seconds)
  return seconds > 0 and M.fmt(seconds + 59) or "+" .. M.fmt(-seconds)
end
local function when(seconds)
  return seconds > 0 and "due in " .. M.fmt(seconds + 59) or M.fmt(-seconds) .. " overdue"
end

-- The break that is due at `now`: "long" (which wins when both are),
-- "short", or nil when none is, as under a break screen. And after it the
-- seconds until the short and the long one are due, 0 or less once they are.
-- Neither is due before s.snoozedUntil (M.snooze), while that is ahead: a
-- break 5 min overdue, snoozed for 10 min a minute ago, is due in 9 min.
-- Last come the seconds it is ahead, nil when it is not.
local function dueAt(s, now)
  local shortIn = s.cfg.breakAfter - (now - s.lastRestAt)
  local longIn = s.cfg.longBreakAfter - (now - s.lastLongRestAt)
  local snoozedFor = nil
  if s.snoozedUntil and now < s.snoozedUntil then
    snoozedFor = s.snoozedUntil - now
    shortIn, longIn = math.max(shortIn, snoozedFor), math.max(longIn, snoozedFor)
  end
  local due = nil
  if not s.onBreak then
    due = longIn <= 0 and "long" or shortIn <= 0 and "short" or nil
  end
  return due, shortIn, longIn, snoozedFor
end

-- Whether a break asked for at `now` is the long one. By the rest clock
-- alone, on purpose: a snooze puts off the reminder, not which break
-- is owed.
local function longDue(s, now)
  return now - s.lastLongRestAt >= s.cfg.longBreakAfter
end

-- The eyes rested for `lasted` seconds, until `now` (a break that ran to
-- its end, or time away): lastRestAt restarts, and the long clock too when
-- it lasted a long break's length (9 min 55 s away: no; 10 min: yes).
-- Returns whether it was such a long rest. The badge has not been up
-- since (s.badgeUpAt, see M.tick): what it showed was the break before.
local function rest(s, now, lasted)
  local long = lasted >= s.cfg.longBreakLength
  s.lastRestAt = now
  s.badgeUpAt = nil
  if long then
    s.lastLongRestAt = now
  end
  return long
end

-- Seconds since the badge last went up, s.badgeUpAt; no end of them when it
-- has not since the last rest.
local function sinceBadgeUp(s, now)
  return now - (s.badgeUpAt or -math.huge)
end

-- The break on screen, s.onBreak: when it went up, how long its countdown
-- runs, and whether it is the long one. nil with no break up.
local function startBreak(s, now, long)
  s.onBreak = { from = now, long = long, length = long and s.cfg.longBreakLength or s.cfg.breakLength }
end

-- A state from what the last load saved (nil on a first run), and a note on
-- what was made of it for the log. A saved table that does not match SAVED
-- raises: it is another version's or a corrupted one, not one to guess at.
function M.new(cfg, saved, now)
  local s = { cfg = cfg, badge = true, lastTickAt = now }
  rest(s, now, math.huge) -- both clocks start now
  if saved == nil then
    return s, "no saved state: clocks start now"
  end

  for key in pairs(saved) do
    if not SAVED[key] then
      error("saved state has an unknown field: " .. tostring(key))
    end
  end
  for key, kind in pairs(SAVED) do
    local value = saved[key]
    if type(value) ~= kind then
      error(string.format("saved state field %s is a %s, not a %s", key, type(value), kind))
    end
    s[key] = value
  end
  -- A long rest is a rest.
  if s.lastLongRestAt > s.lastRestAt then
    error("saved state does not have lastLongRestAt <= lastRestAt")
  end

  -- Hammerspoon was not running (reboot, quit), so nobody counted. Taken as
  -- rest here, not left to the first tick, which would greet a login with
  -- the return sound.
  local gap = now - s.lastTickAt
  s.lastTickAt = now
  if gap >= cfg.asleepAfter then
    rest(s, now, gap)
    return s, string.format("saved state restored; not running for %s, taken as rest", M.fmt(gap))
  end
  return s, "saved state restored; " .. M.fmt(now - s.lastRestAt) .. " since the last rest"
end

function M.saved(s)
  local out = {}
  for key in pairs(SAVED) do
    out[key] = s[key]
  end
  return out
end

-- Whether two M.saved tables, `a` the earlier, differ in nothing but what
-- moves at every tick: lastTickAt, and with it a rest clock while time away
-- runs on, which restarts at each tick and so equals lastTickAt in both.
-- eye_breaks.lua need not write such a one at each second of a break: M.new
-- reads lastTickAt only against asleepAfter, minutes, and a rest clock that
-- is seconds behind is no different.
--
--   a (written)            b (now)                same?
--   rest 11:00, tick 11:20  rest 11:00, tick 11:21  yes: only the tick moved
--   rest 11:00, tick 11:20  rest 11:21, tick 11:21  no: a rest was credited
--   rest 11:21, tick 11:21  rest 11:22, tick 11:22  yes: that rest runs on
--   rest 11:22, tick 11:22  rest 11:30, tick 11:31  no: back, the clock runs
function M.sameButTick(a, b)
  for key in pairs(SAVED) do
    local runsOn = a[key] == a.lastTickAt and b[key] == b.lastTickAt
    if key ~= "lastTickAt" and a[key] ~= b[key] and not runsOn then
      return false
    end
  end
  return true
end

-- Advance to obs.now. obs = { now = <epoch s>, idle = <s since the last
-- input>, locked = <bool>, watching = <function: the name of an app keeping
-- the display awake, or nil> }. Returns what happened, for the log and
-- sounds:
--   { kind = "break_done", long = <bool>,      a long break is a long rest;
--     locked = <bool> }                        locked: nobody saw it end
--   { kind = "returned", away = <s>, sound = <bool>, longRest = <bool> }
--   { kind = "badge_hidden", app = <name> }    the badge is down over what
--   { kind = "badge_unhidden", app = <name> }  that app shows; and no longer
--   { kind = "badge_glimpse", app = <name> }   down over it, up for a moment
--   { kind = "watching", app = <name> }        idle, but not away: see below
--   { kind = "watching_ended", app = <name> }
function M.tick(s, obs)
  local cfg, now, events = s.cfg, obs.now, {}
  local gap = now - s.lastTickAt
  s.lastTickAt = now

  -- The app keeping the display awake, if any. obs.watching() costs a
  -- process, so it is asked only when the answer is used: idle is long
  -- enough to be away, which a video makes it not; or the badge would be
  -- up, which a video keeps down. And not under a lock or after sleep,
  -- which are away whatever plays.
  local asleep = gap >= cfg.asleepAfter
  local idleLong = obs.idle >= cfg.awayAfter
  local badgeWanted = s.badge and dueAt(s, now) ~= nil
  local holder = nil
  if (idleLong or badgeWanted) and not obs.locked and not asleep then
    holder = obs.watching()
  end

  -- The badge stays down over what is being watched (s.hiding is the app).
  local hiding = badgeWanted and holder or nil
  if hiding ~= s.hiding then
    table.insert(events, { kind = hiding and "badge_hidden" or "badge_unhidden", app = hiding or s.hiding })
    s.hiding = hiding
  end

  -- Down, it comes up for a glimpse every glimpseEvery. s.badgeUpAt is when
  -- the badge last went up: the last tick with nothing hiding it, or the
  -- start of the last glimpse; nil when it has not since the last rest, as
  -- on a break that came due under the video, which so shows at once. The
  -- glimpse lasts glimpseLength from there (M.view), and eye_breaks.lua
  -- ticks by the second to take it down.
  if not hiding then
    if badgeWanted then
      s.badgeUpAt = now
    end
  elseif sinceBadgeUp(s, now) >= cfg.glimpseEvery then
    s.badgeUpAt = now
    table.insert(events, { kind = "badge_glimpse", app = hiding })
  end

  -- Watching: idle for awayAfter, but an app keeps the display awake.
  local watching = idleLong and holder or nil
  if watching ~= s.watching then
    table.insert(events, { kind = watching and "watching" or "watching_ended", app = watching or s.watching })
    -- A new stretch starts where the idle time did.
    if watching and not s.watching then
      s.watch = { from = now - obs.idle }
    end
    s.watching = watching
  end
  -- The stretch is kept after it ends, for the menu: opening the menu is
  -- input, so "watching now" is over by the time anyone could read it.
  if watching then
    s.watch.app, s.watch.to = watching, now
  end

  -- Idle time counts from when the watching stopped: a video that ends at
  -- 11:00 after 40 idle minutes makes it away at 11:05, not at once. Input
  -- after the stretch is later than its end, so obs.idle is then the smaller.
  local idleFor = s.watch and math.min(obs.idle, now - s.watch.to) or obs.idle

  -- Away: idle or asleep for their thresholds, or locked. `unseen` is how
  -- far back the away time starts: the idle or sleep time, or 0 for a
  -- lock, which starts it at the lock. Rest is credited once it has lasted
  -- a break's length, so locking for 5 s is not a break; a long rest once
  -- it has lasted a long break's. A break on screen is left to its
  -- countdown, below: it went up at a click, so the time away began after
  -- it, and cannot cover it before the countdown has run out too.
  local idle = idleFor >= cfg.awayAfter
  if obs.locked or idle or asleep then
    local unseen = math.max(idle and idleFor or 0, asleep and gap or 0)
    s.awaySince = s.awaySince or (now - unseen)
    local awayFor = now - s.awaySince
    if awayFor >= cfg.breakLength then
      s.awayRested, s.awayLong = true, rest(s, now, awayFor)
    end
  elseif s.awaySince then
    -- Back at the screen.
    if s.awayRested then
      local awayFor = now - s.awaySince
      table.insert(
        events,
        { kind = "returned", away = awayFor, sound = awayFor >= cfg.returnSoundAfter, longRest = s.awayLong }
      )
    end
    s.awaySince, s.awayRested, s.awayLong = nil, nil, nil
  end

  -- The break on screen runs out whether anyone is at the screen or not:
  -- 5 s of it and then 25 s under a lock is its 30 s all the same.
  local b = s.onBreak
  if b and now >= b.from + b.length then
    rest(s, now, b.length)
    table.insert(events, { kind = "break_done", long = b.long, locked = obs.locked })
    s.onBreak = nil
  end
  return events
end

-- The user's actions. None of them is rest, so the clocks stay; but see
-- M.skip for the long break taken down part-way.

-- A break now: short, long, or the due one (the badge's click; returns
-- whether that was the long one).
function M.breakNow(s, now)
  startBreak(s, now, false)
end

function M.longBreakNow(s, now)
  startBreak(s, now, true)
end

function M.dueBreakNow(s, now)
  local long = longDue(s, now)
  startBreak(s, now, long)
  return long
end

-- Take the break screen down before its end. That is no rest, with one
-- exception: a break that was up for a short one's length has been a short
-- rest (skip at 0:40 of 10:00 -> the rest clock restarts, the long one runs
-- on). That is a long break: a short one has run out by then. Returns
-- whether that was so.
function M.skip(s, now)
  local b = s.onBreak
  local rested = b ~= nil and now - b.from >= s.cfg.breakLength
  if rested then
    rest(s, now, now - b.from)
  end
  s.onBreak = nil
  return rested
end

-- Snooze the due break: none is due from `now` for snoozeFor, or with
-- `long` for longSnoozeFor. Returns whether a break was due; with none,
-- nothing changes. Like the break on screen it is not saved, so a reload
-- inside it brings the badge back. The badge counts as not shown since
-- (s.badgeUpAt, see M.tick): what comes due at the end is to show at once,
-- video or not.
function M.snooze(s, now, long)
  if dueAt(s, now) == nil then
    return false
  end
  s.snoozedUntil = now + (long and s.cfg.longSnoozeFor or s.cfg.snoozeFor)
  s.badgeUpAt = nil
  return true
end

function M.setBadge(s, on)
  s.badge = on
end

-- What to show at `now`:
--   since        s since the last rest
--   sinceLong    s since the last rest of a long break's length
--   shortWhen    the short break against its due time, for the menu:
--                "due in 3m" or "29m overdue"
--   longWhen     the same for the long break
--   title        the menu-bar clock, and the badge's text: the time until
--                the next break is due ("3m"), then how long the due one
--                has been ("+29m"); "break" while one is on screen
--   overlay      { remaining = <s>, long = <bool> } while a break is on
--                screen, else nil
--   due          the break that is due, which a click on the badge brings:
--                "short" (breakAfter since the last rest) or "long" (which
--                wins); nil when none is, as under a break screen. It
--                colours the badge and the menu-bar clock.
--   badge        whether the badge is up: a break is due, the badge is
--                switched on, and nothing hides it, or it does and this is
--                a glimpse
--   hiddenBy     the app whose video (or call) the badge stays down over,
--                as of the last tick; nil when the badge is not wanted
--   glimpse      whether the badge is up over that app for a moment: the
--                glimpseLength after it went up. Ticks must then come by
--                the second, to take it down on time.
--   watched      { app = <name>, from = <epoch s>, to = <epoch s> }: the
--                last idle stretch that was not rest because that app kept
--                the display awake. Only while it explains the clock, i.e.
--                until the next rest; else nil.
--   badgeOn      the badge's toggle, for the menu
--   snoozed      the time a snooze still runs, as the title counts it
--                ("14m"); nil with none
function M.view(s, now)
  local due, shortIn, longIn, snoozedFor = dueAt(s, now)
  local v = {
    since = now - s.lastRestAt,
    sinceLong = now - s.lastLongRestAt,
    shortWhen = when(shortIn),
    longWhen = when(longIn),
    badgeOn = s.badge,
    snoozed = snoozedFor and countdown(snoozedFor),
    watched = s.watch and s.watch.to > s.lastRestAt and s.watch or nil,
  }

  local b = s.onBreak
  if b then
    v.overlay = { remaining = math.max(0, b.from + b.length - now), long = b.long }
    v.title = "break"
    return v
  end

  -- The number is the due break's, the long one's when both are; with
  -- neither due, the nearer one's.
  v.due = due
  v.title = countdown(due == "long" and longIn or math.min(shortIn, longIn))
  local wanted = s.badge and due ~= nil
  v.hiddenBy = wanted and s.hiding or nil
  v.glimpse = v.hiddenBy ~= nil and sinceBadgeUp(s, now) < s.cfg.glimpseLength
  v.badge = wanted and (not v.hiddenBy or v.glimpse)
  return v
end

return M
