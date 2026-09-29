-- Close an iTerm2 bell banner once its tab gets focus, as iTerm2 already
-- clears the tab's own bell icon then. iTerm2 never withdraws the macOS
-- notification it posted ("Session <name> #<n> just rang a bell!"), and with
-- the Persistent alert style (clear_notifications.lua) the banners otherwise
-- pile up until alt+0 clears them all.
--
--   Notification Center                         iTerm2
--   new banner (AXLayoutChanged)                tab switch (AXFocusedUIElementChanged)
--        |                                      or iTerm2 activated
--        v                                           |
--   resolve: which session rang?                     v
--     tab #<n>, whose bellCount rose,          focused session S
--     then the name to break a tie                   |
--        |                                           v
--        +--> pending[session][banner id] --> close every banner pending for S
--                                              (expanding an iTerm2 stack
--                                               first: only then are its
--                                               older banners closable)
--
-- The banner text cannot name its tab later: <n> is the tab's position when
-- it rang, and tabs shift as others open, close or move; names repeat
-- ("fish:~") and change (a job name, Claude's animated first character). So
-- the owner is resolved the moment the banner appears, from bellCount, a
-- per-session counter iTerm2 bumps on every bell, and <n> and the name only
-- narrow the candidates down.
local M = {}

local notifications = require("clear_notifications")

local ITERM2 = "com.googlecode.iterm2"
-- Any iTerm2 notification's AXDescription starts with ITERM2_PREFIX, a bell
-- banner's with BELL_PREFIX and matches BELL_PATTERN (English), e.g.
--   "iTerm2, Bell, Session fish:~ #2 just rang a bell!"
local ITERM2_PREFIX = "iTerm2, "
local BELL_PREFIX = "iTerm2, Bell, "
local BELL_PATTERN = "^iTerm2, Bell, Session (.+) #(%d+) just rang a bell!"
local EXPAND_DELAY = 0.5 -- seconds for an expanded stack's banners to appear
-- Notification Center and iTerm2 fire their events in bursts (a banner
-- sliding in, iTerm2 activating plus its focus change); each burst is
-- handled once, after it settles.
local SCAN_DELAY = 0.15
local FOCUS_DELAY = 0.05

M.pending = {} -- session id -> set of its banner ids, until it gets focus
M.seen = {} -- banner ids already looked at, bell banner or not
M.bells = {} -- session id -> bellCount when its last banner was resolved

local function fail(msg)
  hs.alert.show("iterm2_bell_banners: " .. msg, 4)
  error("iterm2_bell_banners: " .. msg)
end

local function startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

-- Run an AppleScript against iTerm2. The timeout caps how long a hung
-- iTerm2 can stall Hammerspoon (the default is 2 minutes); a failure is a
-- broken setup, so it raises, naming the usual cause.
local function iterm2(what, script)
  local ok, value, raw = hs.osascript.applescript("with timeout of 2 seconds\n" .. script .. "\nend timeout")
  if not ok then
    fail(
      what
        .. " failed (allow Hammerspoon to control iTerm2 in System Settings > "
        .. "Privacy & Security > Automation): "
        .. hs.inspect(raw)
    )
  end
  return value
end

-- Every session of every iTerm2 window with its tab's position (the <n> of
-- the banner), name and bellCount. A record per session, not a list: an
-- unset variable comes back as missing value, which a list would drop and
-- shift the rest; a record only loses that key. bellCount is unset until a
-- session's first bell, so absent means 0.
local SESSIONS = [[
tell application "iTerm2"
  set out to {}
  repeat with w in windows
    set n to 0
    repeat with t in tabs of w
      set n to n + 1
      repeat with s in sessions of t
        tell s to set end of out to {tabNumber:n, sessionId:(id), sessionName:(name), bells:(variable named "bellCount")}
      end repeat
    end repeat
  end repeat
  return out
end tell]]

local function sessions()
  local list = iterm2("listing iTerm2 sessions", SESSIONS)
  for _, s in ipairs(list) do
    s.bells = tonumber(s.bells or "0")
  end
  return list
end

-- The session a new bell banner belongs to (see the header for why these
-- keys). A rise alone is not enough: a bell in the active session rings
-- without a banner. Anything but exactly one candidate is reported rather
-- than guessed, since closing the wrong tab's banner hides a bell that still
-- needs attention. One expected case: banners already on screen when
-- Hammerspoon loaded, hidden in a stack, have no rise left to match once the
-- stack is expanded.
local function resolve(desc)
  local name, n = desc:match(BELL_PATTERN)
  if not name then
    fail("bell banner text changed, cannot parse: " .. desc)
  end
  n = tonumber(n)
  local rose = {}
  for _, s in ipairs(sessions()) do
    if s.tabNumber == n and s.bells > (M.bells[s.sessionId] or 0) then
      table.insert(rose, s)
    end
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

-- Record the owner of each new bell banner. With no iTerm2 banner left on
-- screen (all focused, clicked, or cleared with alt+0), nothing is pending
-- any more; stacked ids cannot be pruned one by one, since a collapsed stack
-- shows only its newest.
local function scan()
  local anyITerm2 = false
  for _, banner in ipairs(notifications.banners()) do
    anyITerm2 = anyITerm2 or startsWith(banner.desc, ITERM2_PREFIX)
    if banner.id and not M.seen[banner.id] then
      M.seen[banner.id] = true
      if startsWith(banner.desc, BELL_PREFIX) then
        local s = resolve(banner.desc)
        M.pending[s.sessionId] = M.pending[s.sessionId] or {}
        M.pending[s.sessionId][banner.id] = true
        print(
          string.format(
            "iterm2_bell_banners: banner %s -> session %s (tab #%d, %s)",
            banner.id:sub(1, 8),
            s.sessionId:sub(1, 8),
            s.tabNumber,
            s.sessionName
          )
        )
      end
    end
  end
  if not anyITerm2 then
    M.pending = {}
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
      print("iterm2_bell_banners: closed banner " .. banner.id:sub(1, 8))
    elseif banner.subrole == "AXNotificationCenterAlertStack" and startsWith(banner.desc, ITERM2_PREFIX) then
      table.insert(stacks, banner.el)
    end
  end
  if next(ids) == nil or expanded or #stacks == 0 then
    return
  end
  for _, stack in ipairs(stacks) do
    stack:performAction("AXPress")
  end
  M.expandTimer = hs.timer.doAfter(EXPAND_DELAY, function()
    close(ids, true)
  end)
end

local CURRENT_SESSION = [[
tell application "iTerm2"
  if (count of windows) is 0 then return ""
  return id of current session of current window
end tell]]

-- On focus in iTerm2 (a tab or pane switch, or iTerm2 coming to the front),
-- close the banners of the session that now has it. Nothing to do, and no
-- round trip to iTerm2, while no bell banner is pending.
local function onFocus()
  if next(M.pending) == nil then
    return
  end
  local front = hs.application.frontmostApplication()
  if not front or front:bundleID() ~= ITERM2 then
    return
  end
  local sid = iterm2("reading iTerm2's current session", CURRENT_SESSION)
  local ids = M.pending[sid]
  M.pending[sid] = nil
  if ids then
    close(ids, false)
  end
end

M.scanTimer = hs.timer.delayed.new(SCAN_DELAY, scan)
M.focusTimer = hs.timer.delayed.new(FOCUS_DELAY, onFocus)

-- Observers, kept in M so they are not garbage-collected. Notification
-- Center runs for the whole login session; iTerm2's observer follows its
-- process through relaunches.
local function watchNotificationCenter()
  local nc = notifications.app()
  M.ncObserver = hs.axuielement.observer.new(nc:pid())
  M.ncObserver:callback(function()
    M.scanTimer:start()
  end)
  M.ncObserver:addWatcher(hs.axuielement.applicationElement(nc), "AXLayoutChanged")
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
  M.itermObserver:start()
end

M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if not app or app:bundleID() ~= ITERM2 then
    return
  end
  if eventType == hs.application.watcher.launched then
    watchITerm2(app)
  elseif eventType == hs.application.watcher.terminated then
    watchITerm2(nil)
  end
end)
M.watcher:start()

-- Banners already on screen at load are left alone: whatever rang them is
-- no longer measurable from bellCount. The current counts are the baseline
-- the next banner is measured against.
for _, banner in ipairs(notifications.banners()) do
  if banner.id then
    M.seen[banner.id] = true
  end
end
watchNotificationCenter()
local iterm = hs.application.applicationsForBundleID(ITERM2)[1]
if iterm then
  for _, s in ipairs(sessions()) do
    M.bells[s.sessionId] = s.bells
  end
  watchITerm2(iterm)
end

return M
