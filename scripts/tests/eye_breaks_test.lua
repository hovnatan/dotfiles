-- eye_breaks_core.lua, the real module, on a made-up clock:
--
--   test --work()/tick()--> core.tick --> events (break_done, returned, ...)
--   test --core.skip() etc--> state   --> core.view: title, badge, overlay
--
-- and display_wake.lua's parse and first on saved `pmset -g assertions`
-- output (PMSET below), at the end.
--
-- Every scenario starts at T0, and names times as minutes after it.
local repo = assert(arg[1], "pass the repo path")
package.path = repo .. "/home/.hammerspoon/?.lua;" .. package.path
local file = assert(io.open(assert(arg[2], "pass the event log path"), "a"))
file:setvbuf("line")
local scenario = "setup"
local function note(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [" .. scenario .. "] " .. string.format(fmt, ...)
  file:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end

local core = require("eye_breaks_core")
local cfg = core.defaults
-- Any moment does: the core reads no calendar, only differences of times.
local T0 = 1800000000

-- Seconds since the epoch at `minutes` (and `seconds`) after T0.
local function at(minutes, seconds)
  return T0 + minutes * 60 + (seconds or 0)
end

local checks = 0
local function check(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    local msg = string.format(fmt, ...)
    note("FAIL %s", msg)
    error("[" .. scenario .. "] " .. msg, 2)
  end
end

-- eq(core.fmt(1380), "23m", "fmt(1380)"): a check that says what it got.
local function eq(got, want, what)
  check(got == want, "%s: got %s, expected %s", what, tostring(got), tostring(want))
end

-- fn(...) must raise, with `pattern` (plain text) in the error.
local function raises(pattern, what, fn, ...)
  local ok, err = pcall(fn, ...)
  check(not ok and tostring(err):find(pattern, 1, true), "%s must raise '%s', got: %s", what, pattern, tostring(err))
end

local function begin(name)
  scenario = name
  note("start")
end

-- A first-run state at T0.
local function start(name)
  begin(name)
  return core.new(cfg, nil, at(0))
end

-- One tick at `now`, with the user typing (idle 1 s) unless `obs` says
-- otherwise. obs.idleSince = <epoch s> is no input since then: idle grows
-- with the clock. Returns the events, each with the time it came at.
local function tick(s, now, obs)
  local o = { now = now, idle = 1, locked = false, watching = function() end }
  for key, value in pairs(obs or {}) do
    o[key] = value
  end
  if o.idleSince then
    o.idle, o.idleSince = now - o.idleSince, nil
  end
  local events = core.tick(s, o)
  for _, event in ipairs(events) do
    event.at = now
    note("+%ds %s", now - T0, event.kind)
  end
  return events
end

-- Tick every 5 s over (from, to]. Any spacing under asleepAfter does;
-- eye_breaks.lua's own ticks are 30 s apart, and 1 s during a break.
local function work(s, from, to, obs)
  local events = {}
  for now = from + 5, to, 5 do
    for _, event in ipairs(tick(s, now, obs)) do
      table.insert(events, event)
    end
  end
  return events
end

-- "break_done@1230 returned@1505": what came, and when after T0.
local function summary(events)
  local parts = {}
  for _, event in ipairs(events) do
    table.insert(parts, event.kind .. "@" .. (event.at - T0))
  end
  return table.concat(parts, " ")
end

local function expect(events, want)
  check(summary(events) == want, "events were '%s', expected '%s'", summary(events), want)
end

-- "+29m short": the badge's text and its colour, or "hidden".
local function badgeLine(view)
  return view.badge and view.title .. " " .. view.due or "hidden"
end

-- --- no break comes by itself; one asked for is rest when it runs out ---------
local s = start("a break asked for")
expect(work(s, at(0), at(20)), "")
eq(core.view(s, at(20)).title, "+5m", "title before the break, 5 min overdue")
core.breakNow(s, at(20))
local v = core.view(s, at(20, 5))
eq(v.overlay.long, false, "a short break is up: long")
eq(v.overlay.remaining, 25, "seconds left at 5 s in")
eq(v.title, "break", "title under the break screen")
eq(v.due, nil, "nothing is due under the break screen")
eq(badgeLine(v), "hidden", "nor is the badge up")
local events = work(s, at(20), at(20, 40))
expect(events, "break_done@1230")
eq(events[1].long, false, "the short break ran out: long")
v = core.view(s, at(20, 40))
eq(v.overlay, nil, "the break screen is down")
eq(v.since, 10, "the rest clock restarts at the break's end: since")
eq(v.sinceLong, 1240, "the long clock runs on: since a long rest")
eq(v.title, "15m", "the title counts down to the next break")
expect(work(s, at(20, 40), at(120)), "")

-- --- time without input is away, and resets the clock ------------------------
s = start("idle counts as rest")
work(s, at(0), at(10))
-- No input from 10:00: away once that is 5 min.
expect(work(s, at(10), at(14, 55), { idleSince = at(10) }), "")
eq(core.view(s, at(14, 55)).since, 895, "under 5 min idle the clock runs: since")
expect(work(s, at(14, 55), at(17), { idleSince = at(10) }), "")
eq(core.view(s, at(17)).since, 0, "since while away")
events = work(s, at(17), at(17, 5))
expect(events, "returned@1025")
eq(events[1].away, 425, "back after 7 min 5 s: away")
eq(events[1].sound, true, "with the sound")

-- --- the lock screen: rest once it has lasted a break's length ---------------
s = start("lock")
work(s, at(0), at(10))
work(s, at(10), at(10, 10), { locked = true })
expect(work(s, at(10, 10), at(10, 15)), "")
eq(core.view(s, at(10, 15)).since, 615, "a 10 s lock is not rest: since")
work(s, at(11), at(11, 30), { locked = true })
eq(core.view(s, at(11, 30)).since, 690, "25 s into a lock is not rest yet: since")
work(s, at(11, 30), at(11, 35), { locked = true })
events = work(s, at(11, 35), at(11, 40))
expect(events, "returned@700")
eq(core.view(s, at(11, 40)).since, 5, "a 30 s lock is rest: since")

-- --- the lock, as eye_breaks.lua ticks it: 30 s apart, and at lock and unlock --
s = start("lock between slow ticks")
work(s, at(0), at(10))
tick(s, at(10, 7), { locked = true }) -- the lock
expect(tick(s, at(10, 30), { locked = true }), "") -- the regular tick under it
-- The unlock ticks twice: still locked, where 35 s of lock is rest, then not.
expect(tick(s, at(10, 42), { locked = true }), "")
eq(core.view(s, at(10, 42)).since, 0, "the clock restarted at the unlock: since")
expect(tick(s, at(10, 42)), "returned@642")
-- A 10 s lock between two regular ticks is not rest, and no return.
tick(s, at(11))
tick(s, at(11, 5), { locked = true })
tick(s, at(11, 15), { locked = true })
expect(tick(s, at(11, 15)), "")
eq(core.view(s, at(11, 15)).since, 33, "a 10 s lock leaves the clock running: since")

-- --- sleep: no ticks, then one with a gap; a long one plays the sound --------
s = start("sleep gap")
work(s, at(0), at(10))
events = work(s, at(40) - 5, at(40, 5))
expect(events, "returned@2405")
eq(events[1].away, 1805, "30 min asleep: away")
eq(events[1].sound, true, "30 min asleep: the sound")
eq(core.view(s, at(40, 5)).since, 5, "since restarts at the wake")
-- Under asleepAfter a gap is a late tick, not sleep.
s = start("late tick")
work(s, at(0), at(10))
expect(work(s, at(11, 55) - 5, at(11, 55)), "")
eq(core.view(s, at(11, 55)).since, 715, "a 115 s gap is no rest: since")
-- Sleep is no guess, so 2 minutes of it is rest where 2 minutes idle is not.
s = start("short sleep")
work(s, at(0), at(10))
events = work(s, at(12) - 5, at(12, 5))
expect(events, "returned@725")
eq(events[1].away, 125, "2 min asleep: away")
eq(events[1].sound, false, "2 min asleep: rest, but no sound")
eq(core.view(s, at(12, 5)).since, 5, "since restarts at the wake")

-- --- a break's countdown runs under a lock, and through sleep ----------------
s = start("lock during a break")
work(s, at(0), at(20))
core.breakNow(s, at(20))
work(s, at(20), at(20, 5))
-- 5 s at the screen and 25 s locked is the break.
expect(work(s, at(20, 5), at(20, 40), { locked = true }), "break_done@1230")

s = start("asleep during a break")
work(s, at(0), at(20))
core.breakNow(s, at(20))
work(s, at(20), at(20, 5))
-- The Mac sleeps at 20:05 and wakes at 25:00.
events = work(s, at(25) - 5, at(25, 5))
expect(events, "break_done@1500 returned@1505")
eq(events[1].long, false, "the short break is over at the wake: long")
eq(events[2].longRest, false, "5 min asleep is no long rest")
s = start("asleep during a long break")
work(s, at(0), at(5))
core.longBreakNow(s, at(5))
work(s, at(5), at(5, 5))
-- Asleep from 5:05 to 25:00, twice the long break's length.
events = work(s, at(25) - 5, at(25))
expect(events, "break_done@1500")
eq(events[1].long, true, "the long break is over at the wake: long")
eq(core.view(s, at(25)).sinceLong, 0, "since a long rest")

-- --- the long break: the badge says which break its click brings --------------
s = start("long break")
work(s, at(0), at(30))
core.breakNow(s, at(30))
expect(work(s, at(30), at(77)), "break_done@1830")
v = core.view(s, at(77))
eq(v.since, 2790, "at 77 min: since")
eq(v.sinceLong, 4620, "at 77 min: since a long rest")
eq(badgeLine(v), "+2m long", "the badge is for a long one, 2 min overdue")
eq(core.dueBreakNow(s, at(77)), true, "its click brings the long break")
v = core.view(s, at(77, 10))
eq(v.overlay.long, true, "a long break is up: long")
eq(v.overlay.remaining, 590, "seconds left at 10 s in")
-- Skipped 10 s in: no rest at all.
eq(core.skip(s, at(77, 10)), false, "skip at 10 s is rest")
eq(core.view(s, at(77, 10)).since, 2800, "the clock runs on: since")
-- Again, skipped 25 s in: still none. And at 40 s: that was a short break's
-- rest, and not a long one's.
core.dueBreakNow(s, at(77, 20))
eq(core.skip(s, at(77, 45)), false, "skip at 25 s is rest")
core.dueBreakNow(s, at(78))
expect(work(s, at(78), at(78, 40)), "")
eq(core.skip(s, at(78, 40)), true, "skip at 40 s is a short rest")
v = core.view(s, at(78, 40))
eq(v.since, 0, "the rest clock restarts: since")
eq(v.sinceLong, 4720, "the long clock runs on: since a long rest")
eq(badgeLine(v), "+3m long", "the badge still asks for the long one")
expect(work(s, at(78, 40), at(94)), "")
v = core.view(s, at(94))
eq(badgeLine(v), "+19m long", "15 min on both are due, and the number is the long one's")
eq(v.shortWhen, "0m overdue", "the menu's line for the short break")
eq(v.longWhen, "19m overdue", "the menu's line for the long break")
-- Sat through: a long rest.
core.dueBreakNow(s, at(94))
events = work(s, at(94), at(104, 5))
expect(events, "break_done@6240")
eq(events[1].long, true, "the long break ran out: long")
v = core.view(s, at(104, 5))
eq(v.since, 5, "both clocks restart: since")
eq(v.sinceLong, 5, "both clocks restart: since a long rest")
eq(v.due, nil, "and nothing is due")
eq(v.title, "15m", "the title counts down to the short break")
eq(v.shortWhen, "due in 15m", "the menu's line for the short break")
eq(v.longWhen, "due in 1h15m", "the menu's line for the long break")
eq(core.dueBreakNow(s, at(105)), false, "the due break is a long one again")
core.skip(s, at(105, 5))
-- The menu's long break, when none is due.
core.longBreakNow(s, at(110))
v = core.view(s, at(110))
eq(v.overlay.long, true, "the menu's long break, with none due: long")
eq(v.overlay.remaining, 600, "its seconds left")
eq(core.skip(s, at(110, 5)), false, "skipped 5 s in is rest")

-- --- time away: a long rest once it lasts a long break's length --------------
s = start("away and the long clock")
work(s, at(0), at(10))
work(s, at(10), at(14), { locked = true })
events = work(s, at(14), at(14, 5))
expect(events, "returned@845")
eq(events[1].longRest, false, "locked under 4 min is a long rest")
v = core.view(s, at(14, 5))
eq(v.since, 5, "a rest all the same: since")
eq(v.sinceLong, 845, "the long clock ran through it: since a long rest")
work(s, at(14, 5), at(20))
-- Locked from 20:05: 9 min 55 s of it is still no long rest, 10 min is.
work(s, at(20), at(30), { locked = true })
eq(core.view(s, at(30)).sinceLong, 1800, "locked 9 min 55 s, no long rest yet: since a long rest")
work(s, at(30), at(30, 5), { locked = true })
events = work(s, at(30, 5), at(30, 10))
expect(events, "returned@1810")
eq(events[1].longRest, true, "locked 10 min is a long rest")
eq(core.view(s, at(30, 10)).sinceLong, 5, "the long clock restarted: since a long rest")
-- 4 min asleep: rest, not a long one.
work(s, at(30, 10), at(35))
events = work(s, at(39) - 5, at(39, 5))
expect(events, "returned@2345")
eq(events[1].away, 245, "4 min asleep: away")
eq(events[1].longRest, false, "4 min asleep is a long rest")
eq(core.view(s, at(39, 5)).sinceLong, 540, "the long clock ran through the sleep: since a long rest")
-- No input for 5 min is away, so rest; a long one only at 10 min.
work(s, at(40), at(49, 55), { idleSince = at(40) })
v = core.view(s, at(49, 55))
eq(v.since, 0, "idle 9 min 55 s is rest: since")
eq(v.sinceLong, 1190, "and no long rest yet: since a long rest")
work(s, at(49, 55), at(50), { idleSince = at(40) })
eq(core.view(s, at(50)).sinceLong, 0, "idle 10 min is a long rest: since a long rest")

-- --- a minute away leaves a long break up, to run out ------------------------
s = start("lock during a long break")
work(s, at(0), at(5))
core.longBreakNow(s, at(5))
work(s, at(5), at(5, 30))
expect(work(s, at(5, 30), at(6, 30), { locked = true }), "")
events = work(s, at(6, 30), at(6, 35))
expect(events, "returned@395")
eq(events[1].away, 60, "a minute locked: away")
eq(events[1].longRest, false, "a minute locked is a long rest")
eq(core.view(s, at(6, 35)).overlay.remaining, 505, "the long break is still up: seconds left")
events = work(s, at(6, 35), at(15, 5))
expect(events, "break_done@900")
eq(events[1].long, true, "and runs out as a long rest: long")

-- --- skip: the screen goes, the clock and the badge stay -----------------------
s = start("skip")
work(s, at(0), at(20))
core.breakNow(s, at(20))
eq(core.skip(s, at(20, 5)), false, "a short break skipped is rest")
v = core.view(s, at(20, 5))
eq(v.overlay, nil, "skip takes the screen down")
eq(v.since, 1205, "and keeps the clock: since")
eq(badgeLine(v), "+5m short", "the badge still asks for the break")

-- --- one number: the time to the next break, then how long it is overdue -----
s = start("title and badge")
-- { seconds after T0, the menu-bar title, the badge: its text and colour }
for _, want in ipairs({
  { 0, "15m", "hidden" },
  { 1, "15m", "hidden" },
  { 60, "14m", "hidden" },
  { 15 * 60 - 1, "1m", "hidden" },
  { 15 * 60, "+0m", "+0m short" },
  { 15 * 60 + 59, "+0m", "+0m short" },
  { 35 * 60, "+20m", "+20m short" },
  { 75 * 60 - 1, "+59m", "+59m short" },
  { 75 * 60, "+0m", "+0m long" },
  { 140 * 60, "+1h05m", "+1h05m long" },
}) do
  v = core.view(s, at(0, want[1]))
  eq(v.title, want[2], "title at " .. want[1] .. " s")
  eq(badgeLine(v), want[3], "badge at " .. want[1] .. " s")
end
-- Switched off it is hidden, and the break is due all the same: the
-- menu-bar clock goes on saying so.
core.setBadge(s, false)
v = core.view(s, at(45))
eq(badgeLine(v), "hidden", "the badge switched off")
eq(v.due, "short", "what is due with the badge off")
eq(v.badgeOn, false, "the switch, for the menu")
-- A short rest at 67:30: the badge goes, and is back for the long break
-- alone, with the short one 8 min off.
s = start("badge for the long break alone")
work(s, at(0), at(67))
core.breakNow(s, at(67))
expect(work(s, at(67), at(67, 30)), "break_done@4050")
v = core.view(s, at(74, 59))
eq(badgeLine(v), "hidden", "a second before the long break is due")
eq(v.title, "1m", "the title counts down to the long break, the nearer one")
eq(v.shortWhen, "due in 8m", "the menu's line for the short break")
eq(badgeLine(core.view(s, at(75))), "+0m long", "at 75 min the long one is due")

-- --- a playing video: idle, but not away -------------------------------------
s = start("watching is not rest")
work(s, at(0), at(10))
local asked = 0
local function chrome()
  asked = asked + 1
  return "Google Chrome"
end
-- No input from 10:00, and Chrome keeps the display awake until 30:00.
-- From 15:00 that is 5 min idle, and a break is due: both ask about Chrome.
expect(work(s, at(10), at(30), { idleSince = at(10), watching = chrome }), "badge_hidden@900 watching@900")
eq(asked, 181, "asked once a tick from 5 min idle on (181 ticks), not before: times asked")
v = core.view(s, at(30))
eq(v.since, 1800, "the clock ran through the video: since")
eq(v.due, "short", "so a break is due")
check(
  v.watched and v.watched.app == "Google Chrome" and v.watched.from == at(10) and v.watched.to == at(30),
  "the view says who held the clock, and from when to when"
)
-- The video ends; still no input. Away 5 min after its end, not at once.
expect(work(s, at(30), at(34, 55), { idleSince = at(10) }), "badge_unhidden@1805 watching_ended@1805")
eq(core.view(s, at(34, 55)).since, 2095, "4 min 55 s after the video the clock still runs: since")
expect(work(s, at(34, 55), at(35), { idleSince = at(10) }), "")
eq(core.view(s, at(35)).since, 0, "5 min after the video it is rest: since")
events = work(s, at(35), at(35, 5))
expect(events, "returned@2105")
eq(events[1].away, 305, "away counts from the video's end: away")
eq(core.view(s, at(35, 5)).watched, nil, "after a rest the old stretch explains nothing: watched")

-- --- input ends the watching; the stretch stays for the menu ------------------
s = start("watching, then input")
work(s, at(0), at(10))
work(s, at(10), at(16), { idleSince = at(10), watching = chrome })
expect(work(s, at(16), at(16, 5), { watching = chrome }), "watching_ended@965")
v = core.view(s, at(16, 5))
eq(v.since, 965, "no rest came of it: since")
eq(v.watched and v.watched.to, at(16), "the stretch is still shown once it is over: its end")

-- --- a video keeps the badge down; the clock and the title's colour stay ------
s = start("a video hides the badge")
work(s, at(0), at(20))
eq(badgeLine(core.view(s, at(20))), "+5m short", "the badge, 5 min overdue, before the video")
-- A video plays from 20:00 to 22:00, with a key pressed now and then.
asked = 0
expect(work(s, at(20), at(22), { watching = chrome }), "badge_hidden@1205")
eq(asked, 24, "asked once a tick while the badge is wanted: times asked")
v = core.view(s, at(22))
eq(badgeLine(v), "hidden", "the badge over the video")
eq(v.hiddenBy, "Google Chrome", "the app the menu names")
eq(v.due, "short", "the break is as due")
eq(v.title, "+7m", "and the title counts on")
expect(work(s, at(22), at(22, 5)), "badge_unhidden@1325")
v = core.view(s, at(22, 5))
eq(badgeLine(v), "+7m short", "the badge is back when the video ends")
eq(v.hiddenBy, nil, "and nothing hides it")
-- Switched off, the badge is not wanted, and nobody is asked.
core.setBadge(s, false)
asked = 0
expect(work(s, at(22, 5), at(23), { watching = chrome }), "")
eq(asked, 0, "not asked with the badge switched off: times asked")
-- A break asked for under the video: its screen comes up, the badge is not
-- wanted, and it comes back hidden once the break was skipped.
core.setBadge(s, true)
work(s, at(23), at(23, 5), { watching = chrome })
core.dueBreakNow(s, at(23, 5))
expect(work(s, at(23, 5), at(23, 10), { watching = chrome }), "badge_unhidden@1390")
core.skip(s, at(23, 10))
expect(work(s, at(23, 10), at(23, 15), { watching = chrome }), "badge_hidden@1395")

-- --- the question costs a process: not asked with input, a lock, or sleep ----
s = start("watching is asked only when idle")
asked = 0
work(s, at(0), at(10), { watching = chrome })
work(s, at(10), at(11), { idle = 600, locked = true, watching = chrome })
work(s, at(20) - 5, at(20), { idle = 600, watching = chrome })
eq(asked, 0, "not asked while typing, locked, or just woken: times asked")
eq(core.view(s, at(20)).since, 0, "a lock and a sleep are rest whatever plays: since")

-- --- saved state: a reload keeps the clocks, a long gap is rest --------------
s = start("save and restore")
work(s, at(0), at(12))
core.setBadge(s, false)
local saved = core.saved(s)
check(saved.cfg == nil and saved.awaySince == nil, "saved holds only the persisted fields")
eq(saved.lastLongRestAt, at(0), "the long clock is saved")
local function restore(now)
  local restored, why = core.new(cfg, saved, now)
  note("restore: %s", why)
  return restored, why
end
v = core.view(restore(at(12, 2)), at(12, 2))
eq(v.since, 722, "a reload keeps the clock: since")
eq(v.badgeOn, false, "and the badge's switch")
v = core.view(restore(at(15)), at(15))
eq(v.since, 0, "3 min not running is rest: since")
eq(v.sinceLong, 900, "and not a long one: since a long rest")
local restored, why = restore(at(50))
v = core.view(restored, at(50))
eq(v.since, 0, "38 min not running is rest: since")
eq(v.sinceLong, 0, "and a long one: since a long rest")
check(why:find("taken as rest", 1, true), "the note says so: %s", why)
-- It was taken as rest at the load, so the first ticks bring no "returned":
-- a login is not greeted with the return sound.
expect(work(restored, at(50), at(50, 10)), "")

-- --- what eye_breaks.lua asks before a write: did more than the time move? ---
s = start("worth a write")
work(s, at(0), at(10))
local written = core.saved(s)
local function same()
  return core.sameButTick(written, core.saved(s))
end
tick(s, at(10, 5))
eq(same(), true, "a tick at the screen moves only lastTickAt: same")
core.setBadge(s, false)
eq(same(), false, "the badge switched off is a change: same")
written = core.saved(s)
-- Locked from 10:10. The rest clock restarts at every tick from 30 s on:
-- the first is a change, the ones after are that rest running on.
work(s, at(10, 5), at(10, 35), { locked = true })
eq(same(), true, "25 s into a lock nothing was credited: same")
tick(s, at(10, 40), { locked = true })
eq(same(), false, "the rest credited at 30 s is a change: same")
written = core.saved(s)
work(s, at(10, 40), at(20, 5), { locked = true })
eq(same(), true, "the rest running on is not, tick after tick: same")
tick(s, at(20, 10), { locked = true })
eq(same(), false, "until it is a long rest, at 10 min: same")
written = core.saved(s)
work(s, at(20, 10), at(25), { locked = true })
eq(same(), true, "which runs on in its turn: same")
expect(tick(s, at(25, 5)), "returned@1505")
eq(same(), false, "back at the screen the clock stops restarting, a change: same")

-- --- saved state that does not fit raises ------------------------------------
begin("bad saved state")
local function state(fields)
  local t = {
    lastRestAt = 1,
    lastLongRestAt = 1,
    lastTickAt = 3,
    badge = true,
  }
  for key, value in pairs(fields) do
    t[key] = value
  end
  return t
end
raises("badge is a string, not a boolean", "a wrong type", core.new, cfg, state({ badge = "yes" }), at(0))
local short = state({})
short.lastTickAt = nil
raises("lastTickAt is a nil, not a number", "a missing field", core.new, cfg, short, at(0))
raises("lastLongRestAt <= lastRestAt", "clocks out of order", core.new, cfg, state({ lastLongRestAt = 2 }), at(0))
saved.surprise = 1
raises("unknown field: surprise", "an unknown field", core.new, cfg, saved, at(0))

-- --- fmt ----------------------------------------------------------------------
begin("fmt")
for seconds, want in pairs({ [0] = "0m", [59] = "0m", [1380] = "23m", [3600] = "1h00m", [3900] = "1h05m" }) do
  eq(core.fmt(seconds), want, "fmt(" .. seconds .. ")")
end

-- --- display_wake: who keeps the display awake, from pmset's output -----------
begin("display_wake")
local wake = require("display_wake")
-- `pmset -g assertions` of 2026-11-17, cut down: a video in Chrome, WhatsApp
-- open, a caffeinate that only holds the system awake.
local PMSET = [[
2026-11-17 13:40:40 -0500
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
   InternalPreventDisplaySleep    1
   PreventUserIdleSystemSleep     1
Listed by owning process:
   pid 566(powerd): [0x000a10de00108d5c] 00:01:39 InternalPreventDisplaySleep named: "com.apple.powermanagement.delayDisplayOff"
	Timeout will fire in 80 secs Action=TimeoutActionTurnOff
   pid 18939(caffeinate): [0x000a119100018b02] 00:00:51 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
	Details: caffeinate asserting for 300 secs
	Localized=THE CAFFEINATE TOOL IS PREVENTING SLEEP.
   pid 14655(WhatsApp): [0x0009102700058c64] 18:13:22 PreventUserIdleDisplaySleep named: "net.whatsapp.idletimer"
   pid 70176(Google Chrome): [0x000a11c000018b0b] 00:00:04 NoIdleSleepAssertion named: "Playing audio"
   pid 70176(Google Chrome): [0x000a11c000058b0a] 00:00:05 NoDisplaySleepAssertion named: "Video Wake Lock"
Kernel Assertions: 0x104=USB,MAGICWAKE
   id=553  level=255 0x4=USB creat= description=com.apple.usb.externaldevice.00200000 owner=USB3.2 Hub
]]
local holders = wake.parse(PMSET)
local seen = {}
for _, holder in ipairs(holders) do
  table.insert(seen, holder.app .. "/" .. holder.kind .. "/" .. holder.name)
end
eq(
  table.concat(seen, " "),
  "WhatsApp/PreventUserIdleDisplaySleep/net.whatsapp.idletimer Google Chrome/NoDisplaySleepAssertion/Video Wake Lock",
  "the display holders, and not powerd's own, the audio or the system-sleep ones"
)
check(wake.first(holders).app == "Google Chrome", "WhatsApp is ignored, Chrome's video is the holder")
check(wake.first({ holders[1] }) == nil, "WhatsApp alone is nobody watching")
check(wake.first({ { app = "caffeinate" } }) == nil, "caffeinate -d is nobody watching")
check(wake.first({ { app = "Hammerspoon" } }) == nil, "the break screen's own hold is nobody watching")

-- An app name with parentheses of its own, and a listing with no holder.
local helper = wake.parse(
  "x\nListed by owning process:\n"
    .. '   pid 9(Google Chrome Helper (Renderer)): [0x00ab] 00:10:00 NoDisplaySleepAssertion named: "Video Wake Lock"  \n'
)
check(#helper == 1 and helper[1].app == "Google Chrome Helper (Renderer)", "an app name with parentheses")
check(#wake.parse("x\nListed by owning process:\nKernel Assertions: 0x4=USB\n") == 0, "an empty listing is no holders")

-- Output it cannot read raises: an empty answer would say "nobody watching".
raises('no "Listed by owning process:" section', "text that is not pmset output", wake.parse, "pmset: unknown option\n")
raises(
  "cannot read this pmset line",
  "an unreadable display line",
  wake.parse,
  "x\nListed by owning process:\n   pid 9 Chrome NoDisplaySleepAssertion Video Wake Lock\n"
)

scenario = "done"
note("PASS: %d checks", checks)
