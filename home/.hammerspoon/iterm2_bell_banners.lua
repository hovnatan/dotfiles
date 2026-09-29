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
--   new bell banner? --> queue            reset the bell baseline of the
--                          |              sessions on screen now and before
--                          v                      |
--   snapshot (iterm2_sessions.js, own process) <--+
--                          |                      |
--                          v                      v
--   resolve: tab #<n>, bellCount rose,    focused session S:
--     name breaks a tie                     close its pending banners
--        |                                  (expanding an iTerm2 stack first)
--        +--> pending[session][banner id] ----^
--
-- The banner text cannot name its tab later: <n> is the tab's position when
-- it rang, and tabs shift as others open, close or move; names repeat
-- ("fish:~") and change (a job name, Claude's animated first character). So
-- the owner is resolved the moment the banner appears, from bellCount, a
-- per-session counter iTerm2 bumps on every bell, and <n> and the name only
-- narrow the candidates down.
--
-- bellCount also rises for bells that post no banner: iTerm2 posts only when
-- a session's bell flag turns on while its tab is off screen (or iTerm2 is
-- in the background), so bells in the tab on screen, in any of its panes,
-- and repeat bells before a visit count without a banner. Left alone, such a
-- rise would make its session a candidate for a later banner at the same
-- tab position (a split pane, another window). So every focus change resets
-- the baseline of the sessions on screen and those that just left it.
local M = {}

local notifications = require("clear_notifications")

local ITERM2 = "com.googlecode.iterm2"
-- Any iTerm2 notification's AXDescription starts with ITERM2_PREFIX, a bell
-- banner's with BELL_PREFIX and matches BELL_PATTERN (English), e.g.
--   "iTerm2, Bell, Session fish:~ #2 just rang a bell!"
local ITERM2_PREFIX = "iTerm2, "
local BELL_PREFIX = "iTerm2, Bell, "
local BELL_PATTERN = "^iTerm2, Bell, Session (.+) #(%d+) just rang a bell!"
local SESSIONS_SCRIPT = hs.configdir .. "/iterm2_sessions.js"
local QUERY_TIMEOUT = 5 -- seconds; the script takes about 0.35
local EXPAND_DELAY = 0.5 -- seconds for an expanded stack's banners to appear
-- A focus change fires a burst (iTerm2 activating plus its focus change);
-- it is handled once, after the burst.
local FOCUS_DELAY = 0.05

M.pending = {} -- session id -> set of its banner ids, until it gets focus
M.seen = {} -- banner ids already looked at, bell banner or not
M.bells = {} -- session id -> bellCount baseline, pruned to live sessions
M.visible = {} -- session ids on screen at the last snapshot
M.queue = {} -- new bell banners { id, desc } waiting for a snapshot
M.waiting = {} -- callbacks for the snapshot being taken or the next one

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

-- Take a snapshot of iTerm2's sessions (see iterm2_sessions.js) off the main
-- thread and hand it to `callback`. One osascript runs at a time; callbacks
-- that arrive meanwhile get the next snapshot, since theirs must postdate
-- the event that asked for it. Callbacks run in the order they asked. A
-- failed or hung script is a broken setup (usually Automation permission),
-- so it raises instead of leaving banners silently unhandled.
local takeSnapshot

-- Not while iTerm2 is closed: the script would launch it. A banner left by
-- an iTerm2 that has quit has no session to belong to, so it is dropped.
-- "Running" is the iTerm2 observer being attached, which the app watcher
-- keeps in step with its launch and quit; hs.application's lookup is not
-- used here, as it has come back empty for running processes.
local function snapshot(callback)
  if not M.itermObserver then
    if #M.queue > 0 then
      log("iTerm2 is not running; dropping %d queued banner(s)", #M.queue)
    end
    M.queue = {}
    return
  end
  table.insert(M.waiting, callback)
  if not M.task then
    takeSnapshot()
  end
end

function takeSnapshot()
  local callbacks = M.waiting
  M.waiting = {}
  local started = hs.timer.secondsSinceEpoch()
  local function done(code, out, err)
    M.task = nil
    M.queryTimer:stop()
    if code ~= 0 then
      fail(
        "iterm2_sessions.js failed (allow Hammerspoon to control iTerm2 in System Settings > "
          .. "Privacy & Security > Automation): "
          .. tostring(err)
      )
    end
    local data = hs.json.decode(out)
    log(
      "snapshot: %d session(s) in %.0f ms for %d caller(s)",
      #data.sessions,
      (hs.timer.secondsSinceEpoch() - started) * 1000,
      #callbacks
    )
    local live = {}
    for _, s in ipairs(data.sessions) do
      live[s.sessionId] = true
    end
    for sid in pairs(M.bells) do
      if not live[sid] then
        M.bells[sid] = nil
      end
    end
    -- Every callback runs even if one raises (else a failed focus step would
    -- also lose the banners queued behind it); the first error is raised
    -- once they all have.
    local firstError
    for _, cb in ipairs(callbacks) do
      local ok, err = pcall(cb, data)
      if not ok and not firstError then
        firstError = err
      end
    end
    if #M.waiting > 0 then
      takeSnapshot()
    end
    if firstError then
      error(firstError, 0)
    end
  end
  M.task = hs.task.new("/usr/bin/osascript", done, { "-l", "JavaScript", SESSIONS_SCRIPT })
  M.queryTimer = hs.timer.doAfter(QUERY_TIMEOUT, function()
    if M.task then
      M.task:terminate()
      M.task = nil
      fail("iterm2_sessions.js took over " .. QUERY_TIMEOUT .. "s; is iTerm2 hung?")
    end
  end)
  M.task:start()
end

-- The session a new bell banner belongs to (see the header for why these
-- keys), or nil. A rise alone is not enough: bells without a banner rise too.
--
-- No candidate at all is expected, and only logged: a banner this module
-- never saw arrive has no rise left to match. That is every banner a
-- Notification Center restart brings back from its history, and any that
-- were already on screen at load, once expanding a stack reveals them. The
-- same goes, rarely, for a bell within a fraction of a second of switching
-- to or from its tab, whose rise the baseline reset can take; that banner
-- then just stays. Several candidates are a real ambiguity and raise:
-- guessing could close the wrong tab's banner and hide a bell that still
-- needs attention.
local function resolve(desc, sessions)
  local name, n = desc:match(BELL_PATTERN)
  if not name then
    fail("bell banner text changed, cannot parse: " .. desc)
  end
  n = tonumber(n)
  local rose = {}
  for _, s in ipairs(sessions) do
    if s.tabNumber == n and s.bells > (M.bells[s.sessionId] or 0) then
      table.insert(rose, s)
    end
  end
  if #rose == 0 then
    log("no session rang for banner '%s', leaving it (arrived unseen)", desc)
    return nil
  end
  local picks = rose
  if #rose > 1 then
    picks = {}
    for _, s in ipairs(rose) do
      if s.sessionName == name then
        table.insert(picks, s)
      end
    end
  end
  if #picks ~= 1 then
    fail(#picks .. " sessions match banner '" .. desc .. "' (tab #" .. n .. ", bell count up): " .. hs.inspect(rose))
  end
  local s = picks[1]
  M.bells[s.sessionId] = s.bells
  return s
end

local function resolveQueued(data)
  local queue = M.queue
  M.queue = {}
  for _, banner in ipairs(queue) do
    local s = resolve(banner.desc, data.sessions)
    if s then
      M.pending[s.sessionId] = M.pending[s.sessionId] or {}
      M.pending[s.sessionId][banner.id] = true
      log("banner %s -> session %s (tab #%d, %s)", short(banner.id), short(s.sessionId), s.tabNumber, s.sessionName)
    end
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
    table.insert(M.queue, { id = id, desc = desc })
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

-- Close the banners in `ids` (a set of banner ids). A single banner is closed
-- directly; an iTerm2 stack is expanded first, since collapsed it offers only
-- Clear All, which would take other tabs' banners with it, and a second pass
-- then finds its older banners as single ones. Ids still missing after that
-- were dismissed some other way (clicked, alt+0).
local function close(ids, expanded)
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
  if next(ids) == nil then
    return
  end
  local missing = {}
  for id in pairs(ids) do
    table.insert(missing, short(id))
  end
  if expanded or #stacks == 0 then
    log("banner(s) %s already gone (clicked or cleared)", table.concat(missing, ","))
    return
  end
  log("expanding %d iTerm2 stack(s) for banner(s) %s", #stacks, table.concat(missing, ","))
  for _, stack in ipairs(stacks) do
    stack:performAction("AXPress")
  end
  M.expandTimer = hs.timer.doAfter(EXPAND_DELAY, function()
    close(ids, true)
  end)
end

-- With no iTerm2 banner left on screen (all focused, clicked, or cleared
-- with alt+0), nothing is pending any more. Stacked ids cannot be pruned one
-- by one, since a collapsed stack shows only its newest.
local function prunePending()
  for _, banner in ipairs(notifications.banners()) do
    if startsWith(banner.desc, ITERM2_PREFIX) then
      return
    end
  end
  log("no iTerm2 banner on screen; nothing pending any more")
  M.pending = {}
end

-- After a focus change: reset the baselines (see the header), then close the
-- banners of the focused session.
local function afterFocus(data)
  local visible = {}
  for _, s in ipairs(data.sessions) do
    if s.visible or M.visible[s.sessionId] then
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
    "focus: session %s%s, %d session(s) with pending banners",
    short(data.current),
    data.frontmost and "" or " (iTerm2 in background)",
    pendingCount
  )
  if pendingCount == 0 then
    return
  end
  prunePending()
  local ids = data.frontmost and M.pending[data.current]
  if ids then
    M.pending[data.current] = nil
    close(ids, false)
  end
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
