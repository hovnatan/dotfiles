-- Close an iTerm2 bell banner once its tab gets focus, as iTerm2 already
-- clears the tab's own bell icon then. iTerm2 never withdraws the macOS
-- notification it posted ("Session <name> #<n> just rang a bell!"), and with
-- the Persistent alert style (clear_notifications.lua) the banners otherwise
-- pile up until alt+0 clears them all.
--
--   Notification Center                      iTerm2
--   AXLayoutChanged on a banner              focus change (tab, pane, app)
--        |  (only that element is read)           |
--        v                                        v
--   new bell banner? --> queue + saved    reset the bell baseline of the
--                        counters         sessions on screen now and before
--                          |                      |
--                          v                      |
--   snapshot (iterm2_sessions.js, own process) <--+
--                          |                      |
--                          v                      v
--   resolve older arrivals: counters     sessions on screen, or gone:
--   rose since their saved baselines      struck from each banner's owners
--        |                                        |
--        v                                        |
--   pending[banner id] = its owners  -------------+
--                                                 v
--                                         a banner with no owner left is
--                                         closed (expanding an iTerm2 stack
--                                         first)
--
-- The banner text cannot identify its session: <n> is the tab's position
-- when it rang, and tabs can shift before even the first snapshot finishes.
-- Match bellCount rises by stable session id instead. Every arrival saves
-- its counter baselines and the current snapshot generation; only a later
-- snapshot may resolve it. A focus change or a failed snapshot cannot erase
-- that evidence while the banner waits.
--
-- The name in the text is not used. It is the session's name when it rang,
-- and the snapshot, 0.4s later, often has another: a bell at the end of
-- `sleep 5` says "Session sleep #2" of a session by then named "fish:~"
-- (11 of 28 banners in a day's log), and Claude animates its first
-- character. Names also repeat, so a match could even pick the wrong pane.
--
-- Several sessions can qualify: concurrent bells, or a session with a rise
-- that posted no banner. Native banners expose no session id. A banner then
-- belongs to all of them and closes once each has been on screen. That can
-- keep a banner longer than needed, and never closes one whose bell is still
-- unseen.
--
-- "On screen" is the tab, not the pane: iTerm2 clears a tab's bell icon when
-- the tab is selected, whichever of its panes has focus, and every pane is
-- in view then. A session that is gone (its tab closed unvisited) has
-- nothing left to look at, so it gives up its banners too.
--
-- bellCount also rises for bells that post no banner: iTerm2 posts only when
-- a session's bell flag turns on while its tab is off screen (or iTerm2 is
-- in the background), so bells in the tab on screen, in any of its panes,
-- and repeat bells before a visit count without a banner. Left alone, such a
-- rise would make its session a candidate for a later banner. Every focus
-- change resets the baseline of sessions on screen and those that just left it. That
-- reset can also take the rise of a bell that did post a banner (iTerm2 in
-- the background, or a bell racing a tab switch), so resolve still accepts
-- such a rise when it arrives within ABSORB_WINDOW seconds of the reset.
-- Once saved with an arrival, the evidence lasts until resolution, even if
-- an error delays the next valid snapshot beyond that window.
local M = {}

local notifications = require("clear_notifications")

local ITERM2 = "com.googlecode.iterm2"
-- Any iTerm2 notification's AXDescription starts with ITERM2_PREFIX, a bell
-- banner's with BELL_PREFIX and matches BELL_PATTERN (English), e.g.
--   "iTerm2, Bell, Session fish:~ #2 just rang a bell!"
local ITERM2_PREFIX = "iTerm2, "
local BELL_PREFIX = "iTerm2, Bell, "
local BELL_PATTERN = "^iTerm2, Bell, Session .+ #(%d+) just rang a bell!"
local SESSIONS_SCRIPT = hs.configdir .. "/iterm2_sessions.js"
-- Seconds. The script takes 0.4 (2 sessions) to 0.7 (8 sessions in 3
-- windows), and about 5 when tabs open or close while it runs and it has to
-- start over. It also waits for as long as iTerm2 serves no Apple Events,
-- which is whenever its main run loop is tracking the mouse: a menu held
-- open, a tab dragged out of its window.
--
--   10:03:44 snapshot asked for, a menu is open
--   10:03:49 SLOW_AFTER: one log line, nothing else
--   10:03:57 menu closed, iTerm2 answers -> snapshot handled as usual
--
-- That is not a failure, so only QUERY_TIMEOUT kills the script and alerts.
-- Until 2026-10-02 the kill came at 5s: that day's waits were 4 to 13s, each
-- "is iTerm2 hung?" alert was false (7 in 8 minutes), and killing bought
-- nothing, as the retry queued behind the same menu. 60 leaves a held menu
-- room and still reports an iTerm2 that never answers.
local SLOW_AFTER = 5
local QUERY_TIMEOUT = 60
-- What osascript reports when iTerm2 is gone before the script starts.
-- Matched on the text where the code says too little: -2700 is the code of
-- every JavaScript error, e.g.
--   "Error: TypeError: undefined is not an object ... (-2700)"
local GONE_ERRORS = { "Application can't be found. (-2700)", "(-600)" }
local EXPAND_DELAY = 0.5 -- seconds for an expanded stack's banners to appear
local ABSORB_WINDOW = 5 -- seconds; a banner is matched ~0.65s after its bell
-- A focus change fires a burst (iTerm2 activating plus its focus change);
-- it is handled once, after the burst.
local FOCUS_DELAY = 0.05

M.pending = {} -- banner id -> set of session ids that may have rung it
M.seen = {} -- banner ids already looked at, bell banner or not
M.bells = {} -- session id -> bellCount baseline, pruned to live sessions
M.visible = {} -- session ids on screen at the last snapshot
M.absorbed = {} -- session id -> { before, at }: a rise a baseline reset took
M.queue = {} -- arrivals { id, desc, baselines, generation } awaiting a newer snapshot
M.waiting = {} -- callbacks for the snapshot being taken or the next one
M.generation = 0 -- incremented at snapshot start, not completion

-- Every step below is logged (event_log.lua), e.g.
--   2026-09-29T16:01:23.412Z banner 282D14E5 -> session 487197CF (tab #2, fish:~)
local log
log, M.logDir = require("event_log").new("iterm2_bell_banners")

local function fail(msg)
  log("ERROR %s", msg)
  hs.alert.show("iterm2_bell_banners: " .. msg, 4)
  error("iterm2_bell_banners: " .. msg)
end

local function short(id)
  return id:sub(1, 8)
end

local function startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

-- Call fn on every item, even after one raises, and return the first error
-- (nil if none) for the caller to raise once its own work is done. So one
-- banner that cannot be handled does not take the ones behind it along.
local function each(items, fn)
  local firstError
  for _, item in ipairs(items) do
    local ok, err = pcall(fn, item)
    if not ok and not firstError then
      firstError = err
    end
  end
  return firstError
end

-- Append `callback` unless the list has it: a burst of focus changes while a
-- snapshot is in flight asks for afterFocus each time, and running it five
-- times over the same snapshot only repeats its log line.
local function addOnce(callbacks, callback)
  for _, waiting in ipairs(callbacks) do
    if waiting == callback then
      return
    end
  end
  table.insert(callbacks, callback)
end

-- Take a snapshot of iTerm2's sessions (see iterm2_sessions.js) off the main
-- thread and hand it to `callback`. One osascript runs at a time; callbacks
-- that arrive meanwhile get the next snapshot, since theirs must postdate
-- the event that asked for it. Callbacks run in the order they asked. A
-- failed or hung script is a broken setup (usually Automation permission),
-- so it raises instead of leaving banners silently unhandled.
local takeSnapshot

-- iTerm2 is gone, as it was seen to be or as a snapshot found out: a banner
-- it left has no session to belong to, so the queue is dropped.
local function dropQueue(why)
  log("%s; dropping %d queued banner(s)", why, #M.queue)
  M.queue = {}
  M.waiting = {}
end

-- Not while iTerm2 is closed: the script would launch it. "Running" is the
-- iTerm2 observer being attached, which the app watcher keeps in step with
-- its launch and quit; hs.application's lookup is not used here, as it has
-- come back empty for running processes.
local function snapshot(callback)
  if not M.itermObserver then
    dropQueue("iTerm2 is not running")
    return
  end
  addOnce(M.waiting, callback)
  if not M.task then
    takeSnapshot()
  end
end

function takeSnapshot()
  local callbacks = M.waiting
  M.waiting = {}
  M.generation = M.generation + 1
  local generation = M.generation
  local started = hs.timer.secondsSinceEpoch()
  local task, timer, slow

  -- Preserve failed work ahead of newer requests. The next event retries
  -- it; an immediate retry loop would keep alerting on missing permission.
  local function failed(msg)
    local waiting = callbacks
    for _, callback in ipairs(M.waiting) do
      addOnce(waiting, callback)
    end
    M.waiting = waiting
    log("retained %d snapshot caller(s) for the next event", #waiting)
    fail(msg)
  end

  local function done(code, out, err)
    -- A snapshot that ran out of time was reported by its timer and killed;
    -- its end arrives here later (34ms, measured), when the next snapshot
    -- may be under way, and must not clear that one's task and timer.
    if M.task ~= task then
      return
    end
    M.task = nil
    timer:stop()
    slow:stop()

    -- iTerm2 quitting fires one last focus change, and the snapshot it asks
    -- for then finds no iTerm2 (the log shows each quit this way: the error,
    -- then "iTerm2 quit" 40ms later). That is the expected end of a session,
    -- so the snapshot's callers are dropped, as snapshot() drops them while
    -- iTerm2 is closed. Any other failure raises; -1743 is the missing
    -- Automation permission.
    if code ~= 0 then
      err = tostring(err):gsub("%s+$", "")
      for _, gone in ipairs(GONE_ERRORS) do
        if err:find(gone, 1, true) then
          dropQueue(string.format("iTerm2 went away during a snapshot for %d caller(s) (%s)", #callbacks, err))
          return
        end
      end
      local hint = err:find("(-1743)", 1, true)
          and " (allow Hammerspoon to control iTerm2 in System Settings > Privacy & Security > Automation)"
        or ""
      failed("iterm2_sessions.js failed" .. hint .. ": " .. err)
    end
    local decoded, data = pcall(hs.json.decode, out)
    if not decoded or type(data) ~= "table" then
      failed("iterm2_sessions.js printed no JSON: " .. tostring(out))
    end
    if data.gone then
      dropQueue(string.format("iTerm2 quit during a snapshot for %d caller(s)", #callbacks))
      return
    end
    data.generation = generation
    log(
      "snapshot: %d session(s) in %.0f ms for %d caller(s)",
      #data.sessions,
      (hs.timer.secondsSinceEpoch() - started) * 1000,
      #callbacks
    )

    -- For the callbacks: which sessions exist, and which are on screen.
    data.live, data.visible = {}, {}
    for _, s in ipairs(data.sessions) do
      data.live[s.sessionId] = true
      data.visible[s.sessionId] = s.visible or nil
    end
    for sid in pairs(M.bells) do
      if not data.live[sid] then
        M.bells[sid] = nil
        M.absorbed[sid] = nil
      end
    end

    -- A failed focus step must not lose the banners queued behind it.
    local firstError = each(callbacks, function(callback)
      callback(data)
    end)
    if #M.waiting > 0 then
      takeSnapshot()
    end
    if firstError then
      error(firstError, 0)
    end
  end

  task = hs.task.new("/usr/bin/osascript", done, { "-l", "JavaScript", SESSIONS_SCRIPT })

  -- Waiting on iTerm2 (see SLOW_AFTER): said once, so a slow snapshot can be
  -- told from a missing one in the log. Banners that arrive meanwhile queue
  -- behind it with their evidence saved, as behind any snapshot in flight.
  slow = hs.timer.doAfter(SLOW_AFTER, function()
    log(
      "snapshot unanswered after %ds for %d caller(s); iTerm2 serves no Apple Events while a menu is open or a tab is dragged, waiting up to %ds",
      SLOW_AFTER,
      #callbacks,
      QUERY_TIMEOUT
    )
  end)
  timer = hs.timer.doAfter(QUERY_TIMEOUT, function()
    if M.task == task then
      M.task = nil
      task:terminate()
      failed("iterm2_sessions.js took over " .. QUERY_TIMEOUT .. "s; is iTerm2 hung?")
    end
  end)

  -- Kept in M so the timers are not garbage-collected before they fire.
  M.task, M.queryTimer, M.slowTimer = task, timer, slow
  task:start()
end

-- Freeze the evidence at arrival, including a recent rise taken by a focus
-- reset. Reading M.bells later would let an earlier snapshot's afterFocus
-- consume this banner's rise, especially during recovery from an error.
local function baselines()
  local now = hs.timer.secondsSinceEpoch()
  local saved = {}
  for sid, count in pairs(M.bells) do
    local a = M.absorbed[sid]
    saved[sid] = a and now - a.at < ABSORB_WINDOW and a.before or count
  end
  return saved
end

-- The sessions that may have rung a new bell banner: none, one, or several
-- that cannot be told apart. A tab's old number cannot rule a session out.
--
-- None is expected, and only logged: a banner this module never saw arrive
-- has no rise left to match. That is every banner a Notification Center
-- restart brings back from its history, and any that were already on screen
-- at load, once expanding a stack reveals them.
local function resolve(banner, sessions)
  if not banner.desc:match(BELL_PATTERN) then
    fail("bell banner text changed, cannot parse: " .. banner.desc)
  end
  local rose = {}
  for _, s in ipairs(sessions) do
    -- Sessions created since the last baseline have never rung before it.
    local base = banner.baselines[s.sessionId] or 0
    if s.bells > base then
      table.insert(rose, s)
    end
  end
  -- The rise of a session that rang alone is used up by its banner. With
  -- several, none is: which of them the banner took it from is not known,
  -- and a subsequent banner must still consider them all. Arrivals already
  -- queued retain their own evidence regardless of this baseline update.
  if #rose == 1 then
    M.bells[rose[1].sessionId] = rose[1].bells
    M.absorbed[rose[1].sessionId] = nil
  end
  return rose
end

local function shortIds(ids)
  local list = {}
  for id in pairs(ids) do
    table.insert(list, short(id))
  end
  table.sort(list)
  return table.concat(list, ",")
end

-- Close the single banners on screen that are in `ids` (a set of banner
-- ids), taking them out of it, and return the iTerm2 stacks on screen.
local function closeSingles(ids)
  local stacks = {}
  for _, banner in ipairs(notifications.banners()) do
    if banner.subrole == "AXNotificationCenterAlert" and ids[banner.id] then
      notifications.press(banner)
      ids[banner.id] = nil
      log("closed banner %s", short(banner.id))
    elseif banner.subrole == "AXNotificationCenterAlertStack" and startsWith(banner.desc, ITERM2_PREFIX) then
      table.insert(stacks, banner.el)
    end
  end
  return stacks
end

-- Close the banners in `ids`. A single banner is closed directly; an iTerm2
-- stack is expanded first, since collapsed it offers only Clear All, which
-- would take other tabs' banners with it, and a second pass EXPAND_DELAY
-- later finds its older banners as single ones. Ids still missing after that
-- were dismissed some other way (clicked, alt+0).
--
--   close({a}) -> stack expanded, M.expanding = {a}, timer
--   close({b}) 0.4s later -> M.expanding = {a, b}, same timer
--   timer -> closes a and b
--
-- Banners that come while a stack is expanding join its second pass: a timer
-- of their own would replace the first in M.expandTimer, which is then free
-- to be collected before it fires, its banners already off the pending list.
local function close(ids)
  local stacks = closeSingles(ids)
  if next(ids) == nil then
    return
  end
  if M.expanding then
    log("banner(s) %s join the stack being expanded", shortIds(ids))
    for id in pairs(ids) do
      M.expanding[id] = true
    end
    return
  end
  if #stacks == 0 then
    log("banner(s) %s already gone (clicked or cleared)", shortIds(ids))
    return
  end

  -- M.expanding is set only once the timer that clears it is: set before a
  -- press that raises, it would send every later banner to a pass that
  -- never comes.
  log("expanding %d iTerm2 stack(s) for banner(s) %s", #stacks, shortIds(ids))
  for _, stack in ipairs(stacks) do
    stack:performAction("AXPress")
  end
  M.expanding = ids
  M.expandTimer = hs.timer.doAfter(EXPAND_DELAY, function()
    local waiting = M.expanding
    M.expanding = nil
    closeSingles(waiting)
    if next(waiting) ~= nil then
      log("banner(s) %s already gone (clicked or cleared)", shortIds(waiting))
    end
  end)
end

-- Strike from each pending banner the owners that hold it no longer: a
-- session on screen with iTerm2 in front, and one that is gone. A banner
-- with no owner left is closed. Run after each focus change, and after new
-- banners are matched, since a bell that raced a switch to its tab (or back
-- to iTerm2) is matched only after the focus change that should have closed
-- it.
local function closeAttended(data)
  local ids = {}
  for id, owners in pairs(M.pending) do
    for sid in pairs(owners) do
      if not data.live[sid] then
        log("session %s of banner %s is gone", short(sid), short(id))
        owners[sid] = nil
      elseif data.frontmost and data.visible[sid] then
        owners[sid] = nil
      end
    end
    if next(owners) == nil then
      M.pending[id] = nil
      ids[id] = true
    end
  end
  if next(ids) ~= nil then
    close(ids)
  end
end

local function resolveQueued(data)
  local queue = {}
  local waiting = M.queue
  M.queue = {}
  -- A's snapshot may finish after B arrives but have read B before it rang.
  -- Leave B for the snapshot requested by B, even though both are queued.
  for _, banner in ipairs(waiting) do
    table.insert(banner.generation < data.generation and queue or M.queue, banner)
  end
  local firstError = each(queue, function(banner)
    local owners = resolve(banner, data.sessions)
    if #owners == 0 then
      log("no session rang for banner '%s', leaving it (arrived unseen)", banner.desc)
      return
    end
    M.pending[banner.id] = {}
    local names = {}
    for _, s in ipairs(owners) do
      M.pending[banner.id][s.sessionId] = true
      table.insert(names, string.format("%s (%s)", short(s.sessionId), s.sessionName))
    end
    if #owners == 1 then
      log("banner %s -> session %s, tab #%d", short(banner.id), names[1], owners[1].tabNumber)
    else
      log(
        "banner %s -> one of %d sessions, closed once each was on screen: %s",
        short(banner.id),
        #owners,
        table.concat(names, ", ")
      )
    end
  end)
  closeAttended(data)
  if firstError then
    error(firstError, 0)
  end
end

-- Record a banner the first time it is seen; a bell banner is queued for the
-- next snapshot. `id` and `desc` as in clear_notifications.banners().
local function consider(id, desc)
  if not id or M.seen[id] then
    return
  end
  M.seen[id] = true
  if startsWith(desc, BELL_PREFIX) then
    log("banner %s arrived: %s", short(id), desc)
    table.insert(M.queue, { id = id, desc = desc, baselines = baselines(), generation = M.generation })
    snapshot(resolveQueued)
  end
end

-- A layout change in Notification Center. Only the element it is about is
-- read: a new banner fires it on itself (a stack on the stack, which then
-- carries the new banner's id and text). The first version walked the whole
-- tree here instead, and once kept Notification Center at 75% CPU and
-- Hammerspoon at 24% for six minutes, right after a Notification Center
-- restart had brought back ~20 old banners; a rerun of the same steps did
-- not loop, so the trigger is not pinned down. Hence the breaker: closing a
-- banner fires about two events (25 closed at once: 54), so alt+0 on even
-- ~150 banners stays under LOOP_EVENTS, while anything feeding itself at 10
-- events a second or more crosses it within LOOP_WINDOW seconds; watching
-- then stops with an alert rather than pinning two processes until noticed.
local LOOP_EVENTS = 300
local LOOP_WINDOW = 30
M.burst = { start = 0, count = 0 }

local function onLayoutChanged(_, element)
  local now = hs.timer.secondsSinceEpoch()
  if now - M.burst.start > LOOP_WINDOW then
    M.burst.start, M.burst.count = now, 0
  end
  M.burst.count = M.burst.count + 1
  if M.burst.count > LOOP_EVENTS then
    M.ncObserver:stop()
    fail(
      "Notification Center fired over "
        .. LOOP_EVENTS
        .. " layout events in "
        .. LOOP_WINDOW
        .. "s; stopped watching it (reload Hammerspoon to resume)"
    )
  end
  local subrole = element:attributeValue("AXSubrole")
  if subrole == "AXNotificationCenterAlert" or subrole == "AXNotificationCenterAlertStack" then
    consider(element:attributeValue("AXIdentifier"), element:attributeValue("AXDescription") or "")
  end
end

-- Every banner on screen, for when events may have been missed (load, and a
-- Notification Center restart).
local function scan()
  for _, banner in ipairs(notifications.banners()) do
    consider(banner.id, banner.desc)
  end
end

-- After a focus change: reset the baselines (see the header), then close the
-- banners whose sessions have all been on screen.
--
-- No scan of the screen here: a banner leaves M.pending on evidence only
-- (its owners all on screen, its session gone, or alt+0 pressed every
-- banner), never because a scan did not show it. Until 2026-09-30 a focus
-- change with banners pending scanned Notification Center and, seeing no
-- iTerm2 banner, emptied M.pending; one such scan came back empty while the
-- banner just matched never left the screen (cause unknown: polled at 30ms,
-- the scan found the banner through app and Space switches and a hover), so
-- the visit to its tab closed nothing. Across all logs that prune fired 7
-- times and close() never once found a banner "already gone". A banner
-- dismissed by hand now stays pending until its tab is visited or its
-- session ends, when close() finds it gone and, if an iTerm2 stack is on
-- screen just then, expands that stack once for nothing.
local function afterFocus(data)
  local visible = {}
  local now = hs.timer.secondsSinceEpoch()
  for _, s in ipairs(data.sessions) do
    if s.visible or M.visible[s.sessionId] then
      local before = M.bells[s.sessionId] or 0
      if s.bells > before then
        M.absorbed[s.sessionId] = { before = before, at = now }
      end
      M.bells[s.sessionId] = s.bells
    end
    if s.visible then
      visible[s.sessionId] = true
    end
  end
  M.visible = visible
  local pendingCount = 0
  for _ in pairs(M.pending) do
    pendingCount = pendingCount + 1
  end
  log(
    "focus: session %s%s, %d banner(s) pending",
    short(data.current),
    data.frontmost and "" or " (iTerm2 in background)",
    pendingCount
  )
  if pendingCount == 0 then
    return
  end
  closeAttended(data)
end

local watchNotificationCenter

-- A focus change in iTerm2: a tab or pane switch, or iTerm2 coming to the
-- front or leaving it.
--
-- First, make sure Notification Center is still the process being watched:
-- it restarts (killall NotificationCenter, a crash, some macOS updates), the
-- old observer then sits on a dead pid and reports nothing, and
-- hs.application.watcher does not report the relaunch (checked on macOS
-- 27). A rescan picks up banners posted in between. While none runs there
-- is nothing to watch yet.
local function onFocus()
  local pid = notifications.pid()
  if pid and pid ~= M.ncPid then
    log("Notification Center restarted (pid %s -> %d), watching it again", tostring(M.ncPid), pid)
    watchNotificationCenter()
    scan()
  end
  snapshot(afterFocus)
end

M.focusTimer = hs.timer.delayed.new(FOCUS_DELAY, onFocus)

-- Observers, kept in M so they are not garbage-collected. Each follows its
-- process through relaunches: iTerm2's through the app watcher below,
-- Notification Center's through onFocus.
function watchNotificationCenter()
  if M.ncObserver then
    M.ncObserver:stop()
  end
  M.ncPid = notifications.pid()
  if not M.ncPid then
    fail("NotificationCenter process not found")
  end
  M.ncObserver = hs.axuielement.observer.new(M.ncPid)
  M.ncObserver:callback(onLayoutChanged)
  M.ncObserver:addWatcher(hs.axuielement.applicationElementForPID(M.ncPid), "AXLayoutChanged")
  M.ncObserver:start()
end

local function watchITerm2(app)
  if M.itermObserver then
    M.itermObserver:stop()
    M.itermObserver = nil
  end
  if not app then
    return
  end
  M.itermObserver = hs.axuielement.observer.new(app:pid())
  M.itermObserver:callback(function()
    M.focusTimer:start()
  end)
  local root = hs.axuielement.applicationElement(app)
  M.itermObserver:addWatcher(root, "AXFocusedUIElementChanged")
  M.itermObserver:addWatcher(root, "AXApplicationActivated")
  M.itermObserver:addWatcher(root, "AXApplicationDeactivated")
  M.itermObserver:start()
end

M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if not app or app:bundleID() ~= ITERM2 then
    return
  end
  if eventType == hs.application.watcher.launched then
    log("iTerm2 launched (pid %d)", app:pid())
    watchITerm2(app)
  elseif eventType == hs.application.watcher.terminated then
    log("iTerm2 quit")
    watchITerm2(nil)
  end
end)
M.watcher:start()

-- alt+0 pressed every banner on screen, ours included.
notifications.onClearAll(function()
  log("alt+0 clears every banner; nothing pending any more")
  M.pending = {}
end)

-- Banners already on screen at load are left alone: whatever rang them is
-- no longer measurable from bellCount. The first snapshot sets every
-- baseline; it is asked for before any banner can be, so banners are
-- measured against it. Only while iTerm2 runs: the script would launch it.
local onScreen = 0
for _, banner in ipairs(notifications.banners()) do
  if banner.id then
    M.seen[banner.id] = true
    onScreen = onScreen + 1
  end
end
watchNotificationCenter()
local iterm = hs.application.applicationsForBundleID(ITERM2)[1]
log(
  "loaded: Notification Center pid %d, %d banner(s) already on screen, iTerm2 %s",
  M.ncPid,
  onScreen,
  iterm and "running" or "not running"
)
if iterm then
  -- The observer first: snapshot() takes it as the sign that iTerm2 runs.
  watchITerm2(iterm)
  snapshot(function(data)
    for _, s in ipairs(data.sessions) do
      M.bells[s.sessionId] = s.bells
      if s.visible then
        M.visible[s.sessionId] = true
      end
    end
  end)
end

return M
