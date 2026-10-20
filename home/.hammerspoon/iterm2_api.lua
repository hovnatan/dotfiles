-- Runs iterm2_api.py, the script on iTerm2's Python API, for as long as
-- iTerm2 runs, and shows its bell banners. The script serves three things:
--
--   bells     a banner for each bell in an iTerm2 tab you are not looking
--             at, closed by itself once that tab is in view; clicking it
--             brings the tab to front. Shown here.
--   Cmd-T     in an ssh tab, a new tab on the same machine. iTerm2 calls
--             the script directly (the Dotfiles profile binds Cmd-T to its
--             ssh_new_tab); nothing of it passes through this module.
--   switcher  every window, and bringing one to front, for
--             iterm2_switcher.lua: M.listWindows and M.activateWindow.
--
-- iTerm2's own bell banners ("Session <name> #<n> just rang a bell!") stay
-- off (the Dotfiles profile's Send Bell Alert, dotfiles.json): they never
-- close, and their text cannot say which session rang. iterm2_api.py knows
-- that exactly, so it decides and this module only shows:
--
--   iTerm2 --Python API--> iterm2_api.py (hs.task, uv run --script)
--                            | stdout, a JSON event per line
--                            v
--   this module   bell  -> hs.notify banner, unless the session's is still up
--                 seen  -> withdrawn (the tab came into view)
--                 gone  -> withdrawn (the session ended)
--                 windows -> the M.listWindows callback waiting, if any
--                            ^
--                            | stdin: "activate <session id>", "list",
--                            |        "window <window id>"
--   banner clicked ----------+
--   M.listWindows / M.activateWindow (the switcher) ---+
--
-- The script runs while iTerm2 does: started at load and at each iTerm2
-- launch, it ends when iTerm2 quits (its connection drops) or when
-- Hammerspoon reloads (its stdin closes). Without it bells go unannounced,
-- Cmd-T does nothing and the switcher cannot open, so any other end raises
-- with the script's last
-- words and starts it again, up to MAX_RESTARTS times in RESTART_WINDOW;
-- past that, and for a script that never says it is ready, it stays off
-- until Hammerspoon reloads or iTerm2 relaunches:
--
--   iTerm2 launch --> start --ready--> running --exit, iTerm2 up--> raise
--        ^                                |                          |
--        |                                | iTerm2 quit: stop it,     | restarts
--        +------------- (none) <----------+ forget it, banners down   | left?
--                          ^                                          |
--                          +---- no: raise "not started again" -------+
--                                yes: start (counted)
--
-- Banners wait until withdrawn only while Hammerspoon's alert style is
-- Persistent (System Settings > Notifications > Hammerspoon; a manual step,
-- see the bell note in scripts/setup_user_symlinks.sh). alt+0 still clears
-- them with every other banner (clear_notifications.lua); withdrawing one
-- already cleared is harmless, and its tab's next bell puts up a new one.
-- A Hammerspoon reload forgets the banners it had up (the new script
-- starts with none pending), so those stay until alt+0.
local M = {}

local ITERM2 = "com.googlecode.iterm2"
-- Hammerspoon's PATH is launchd's, without the Nix profile.
local UV = os.getenv("HOME") .. "/.nix-profile/bin/uv"
local SCRIPT = hs.configdir .. "/iterm2_api.py"
-- Seconds. From start to "ready": about 0.2 once uv has the environment
-- cached, up to tens of seconds the first time, when it downloads the
-- iterm2 package; iTerm2 also starts its API server a moment after launch.
local READY_TIMEOUT = 60
-- Seconds after the script ends before judging that end: the connection
-- drop when iTerm2 quits can reach the script before the app watcher hears
-- of the quit.
local EXIT_GRACE = 2
-- A script that ends while iTerm2 runs is started again at most this many
-- times in this many seconds: enough for a one-off (a bug hit once), not
-- for a script that fails at every start.
local MAX_RESTARTS = 3
local RESTART_WINDOW = 300

M.banners = {} -- session id -> its hs.notify banner, or BROKEN
-- A bell whose banner could not be made (that error alerted then): its
-- session's seen and gone have nothing to withdraw, and are no new error.
local BROKEN = {}
M.restarts = {} -- os.time() of each restart within RESTART_WINDOW

-- Every event is logged (event_log.lua), the script's own stderr lines
-- included, e.g.
--   2026-10-12T23:52:06.332Z iterm2_api.py: ... bell in 4C7800E0 ('fish:~/.dotfiles', tab #1, ...): banner
--   2026-10-12T23:52:06.334Z banner up for 4C7800E0: fish:~/.dotfiles
local log
log, M.logDir = require("event_log").new("iterm2_api")

-- fail() alerts and raises; guarded() alerts what no fail() did (failure.lua).
local failure = require("failure")
local fail, guarded = failure.new("iterm2_api", log)

local function short(id)
  return id:sub(1, 8)
end

local function withdraw(sid, why)
  local banner = M.banners[sid]
  if not banner then
    fail(string.format("session %s has no banner to withdraw (%s)", sid, why))
  end
  if banner == BROKEN then
    M.banners[sid] = nil
    log("no banner to withdraw for %s (%s): it failed to show", short(sid), why)
    return
  end
  banner:withdraw()
  M.banners[sid] = nil
  log("banner withdrawn for %s: %s", short(sid), why)
end

local function withdrawAll(why)
  for sid in pairs(M.banners) do
    withdraw(sid, why)
  end
end

-- Whether a banner is still up: one dismissed by hand (alt+0, its close
-- button) leaves Hammerspoon's delivered list, whose entries compare equal
-- to the object that sent them (both checked on macOS 27).
local function isUp(banner)
  for _, delivered in ipairs(hs.notify.deliveredNotifications()) do
    if delivered == banner then
      return true
    end
  end
  return false
end

-- The window list asked and not yet answered (listWindows), if any:
--   { callback = fn, asked = <seconds>, timer = <its time limit>, late = bool }
-- Dropped when answered, and with the run that was asked: a new run never
-- saw the question.
local function forgetListing()
  if M.listing then
    M.listing.timer:stop()
    M.listing = nil
  end
end

-- What each event does. The script sends every bell of a tab not in view;
-- a session keeps one banner, and a new one only once that was dismissed.
local handlers = {
  ready = function(event)
    M.readyTimer:stop()
    M.ready = true
    log("iterm2_api.py ready, watching %d session(s)", event.sessions)
  end,
  bell = function(event)
    local sid = event.session
    local old = M.banners[sid]
    if old == BROKEN then
      log("bell in %s: its last banner failed to show, a new one", short(sid))
    elseif old and isUp(old) then
      log("bell in %s: its banner is still up", short(sid))
      return
    elseif old then
      log("bell in %s: its banner was dismissed, a new one", short(sid))
    end
    M.banners[sid] = BROKEN -- until the banner below is up

    -- The icon on the left is always the sender's, Hammerspoon's: the
    -- private setIdImage that would replace it shows nothing on macOS 27.
    -- So iTerm2's icon goes on the right, as the banner's content image.
    local icon = hs.image.imageFromAppBundle(ITERM2)
    if not icon then
      fail("no icon for " .. ITERM2 .. ": is iTerm2 still installed?")
    end
    M.banners[sid] = hs.notify
      .new(function()
        log("banner clicked for %s", short(sid))
        M.activate(sid)
      end, {
        title = event.name .. " rang a bell",
        subTitle = event.window ~= "" and event.window or nil,
        informativeText = "Tab #" .. event.tab .. "; click to go there",
        contentImage = icon,
        withdrawAfter = 0, -- 0: never on its own (the default is 5s)
        hasActionButton = false,
      })
      :send()
    log("banner up for %s: %s", short(sid), event.name)
  end,
  seen = function(event)
    withdraw(event.session, "its tab is in view")
  end,
  gone = function(event)
    withdraw(event.session, "its session ended")
  end,
  -- The reply to listWindows' "list"; one past its time was alerted then,
  -- and goes nowhere. The caller runs guarded, not left to feed(): its
  -- error is the caller's, not this line's, and needs no list in it.
  windows = function(event)
    local listing = M.listing
    if not listing then
      fail("iterm2_api.py sent a window list nobody asked for")
    end
    forgetListing()
    local took = hs.timer.secondsSinceEpoch() - listing.asked
    if listing.late then
      log("window list: %d window(s), %.1fs after asking: dropped", #event.windows, took)
      return
    end
    log("window list: %d window(s) in %.0f ms", #event.windows, took * 1000)
    guarded(listing.callback, event)
  end,
}

-- One line of the script's stdout: an event, or a message the iterm2
-- package printed itself (it does, on some connection problems), which is
-- only logged; the script's exit says whether it mattered.
local function onLine(line)
  if line:sub(1, 1) ~= "{" then
    log("iterm2_api.py stdout: %s", line)
    return
  end
  local ok, event = pcall(hs.json.decode, line)
  local handler = ok and type(event) == "table" and handlers[event.event]
  if not handler then
    fail("iterm2_api.py sent an event this module does not know: " .. line)
  end
  handler(event)
end

-- Output arrives in chunks that need not end at a line break; the partial
-- last line waits in `buffers` for the rest.
--
-- A line that raises (fail() has logged and alerted it by then) must not
-- end the stream: hs.task stops calling a stream callback that raised, the
-- script's stdout pipe then fills, and it blocks on its next event with
-- every later bell, seen and click stuck behind it. So each line runs on
-- its own, and its error goes to the Console as well. An error fail() did
-- not raise (a handler's own: a missing field, say) is alerted here.
local buffers = { out = "", err = "" }

local function feed(stream, chunk, final)
  local text = buffers[stream] .. (chunk or "")
  if final and text ~= "" and text:sub(-1) ~= "\n" then
    text = text .. "\n"
  end
  buffers[stream] = text:match("[^\n]*$")
  for line in text:gmatch("([^\n]*)\n") do
    if stream == "out" then
      local ok, err = pcall(onLine, line)
      if not ok and not failure.alerted(err) then
        ok, err = pcall(fail, string.format("handling %s failed: %s", line, tostring(err)))
      end
      if not ok then
        print(tostring(err))
      end
    else
      log("iterm2_api.py: %s", line)
    end
  end
end

local start, restart

-- The script ended. Its banners are withdrawn whatever the reason: their
-- sessions are gone (iTerm2 quit) or nothing would ever close them.
local function onExit(task, code, out, err)
  if task ~= M.task then
    return -- an earlier run, already replaced
  end
  feed("out", out, true)
  feed("err", err, true)
  M.task = nil
  M.ready = false
  M.readyTimer:stop()
  forgetListing()
  log("iterm2_api.py exited %d", code)
  withdrawAll("iterm2_api.py exited")
  M.exitTimer = hs.timer.doAfter(EXIT_GRACE, function()
    if M.itermRunning then
      restart(string.format("iterm2_api.py exited %d while iTerm2 runs", code))
    end
  end)
end

-- Start the script again after `why`, unless it has been started again too
-- often of late; raises either way, so the end is alerted.
function restart(why)
  local now = os.time()
  local recent = {}
  for _, t in ipairs(M.restarts) do
    if now - t < RESTART_WINDOW then
      table.insert(recent, t)
    end
  end
  M.restarts = recent
  if #recent >= MAX_RESTARTS then
    fail(
      string.format(
        "%s, %d times in %ds: not started again (bell banners, Cmd-T and the switcher stay off"
          .. " until Hammerspoon reloads); its log: %s",
        why,
        #recent + 1,
        RESTART_WINDOW,
        M.logDir
      )
    )
  end
  table.insert(M.restarts, now)
  start()
  fail(string.format("%s; started again; its log: %s", why, M.logDir))
end

function start()
  -- A relaunch within EXIT_GRACE of the last run's end (an upgrade's) is
  -- not that run failing while iTerm2 runs.
  if M.exitTimer then
    M.exitTimer:stop()
  end
  buffers.out, buffers.err = "", ""
  M.ready = false
  forgetListing()
  local task
  task = hs.task.new(UV, function(code, out, err)
    onExit(task, code, out, err)
  end, function(_, out, err)
    feed("out", out)
    feed("err", err)
    return true -- keep streaming
  end, { "run", "--quiet", "--script", SCRIPT })

  -- Taken as the running task only once started: a failed start must not
  -- leave M.task set, or no later iTerm2 launch would try again.
  if not task:start() then
    fail("could not start " .. UV .. " (is uv in the Nix profile?)")
  end
  M.task = task
  -- Not started again: a script that cannot connect in a minute (iTerm2's
  -- "allow this script" prompt unanswered, its Python API off) would not
  -- connect on a retry either. Forgotten first, so its exit is not judged.
  M.readyTimer = hs.timer.doAfter(READY_TIMEOUT, function()
    if M.task == task then
      M.task = nil
      task:terminate()
      fail(
        string.format(
          "iterm2_api.py not ready after %ds (is iTerm2's Python API on, its prompt"
            .. " answered?); bell banners, Cmd-T and the switcher stay off until Hammerspoon"
            .. " reloads; its log: %s",
          READY_TIMEOUT,
          M.logDir
        )
      )
    end
  end)
  log("started iterm2_api.py (pid %d)", task:pid())
end

-- What other modules ask of the script (iterm2_switcher.lua). One asked
-- before its "ready" waits in its stdin and is read once it connects.
local function send(command)
  if not M.task then
    fail("iterm2_api.py is not running (bell banners and Cmd-T are off too); its log: " .. M.logDir)
  end
  M.task:setInput(command .. "\n")
end

-- Bring session `sid` to front: its tab, its window, iTerm2.
function M.activate(sid)
  send("activate " .. sid)
end

-- Bring window `wid` (an id from listWindows) to front, and iTerm2.
function M.activateWindow(wid)
  send("window " .. wid)
end

-- Every window, handed to `callback` as the script's "windows" event
-- (iterm2_api.py list_windows) once it replies, e.g.
--   { current = "<id>", windows = { { window = "<id>", title = "~/.dotfiles", number = 6, tabs = 3 } } }
-- An error `callback` raises is alerted once (failure.lua): as the caller's
-- own if it alerted it, else as an unexpected error here.
--
-- Asked only of a script that is ready, one at a time, and answered within
-- `seconds` or alerted and dropped. So a click never queues a question
-- behind a script still connecting (up to READY_TIMEOUT after an iTerm2
-- launch) or stuck, nor pops the picker up long after it:
--
--   listWindows --not ready, or a list still unanswered--> raise
--        | "list"
--        v
--   asked --reply--> callback
--     | `seconds` pass
--     v
--   late: raise --reply--> logged, dropped; the next one can be asked
--
-- A script that ends first answers none: the next run starts with none.
function M.listWindows(seconds, callback)
  if M.task and not M.ready then
    fail("iterm2_api.py is still connecting to iTerm2 (just launched?): try again in a moment")
  end
  if M.listing then
    fail(
      string.format(
        "iterm2_api.py has not answered the last window list, asked %.1fs ago; its log: %s",
        hs.timer.secondsSinceEpoch() - M.listing.asked,
        M.logDir
      )
    )
  end
  send("list")
  local listing = { callback = callback, asked = hs.timer.secondsSinceEpoch() }
  listing.timer = hs.timer.doAfter(seconds, function()
    listing.late = true
    fail(string.format("iterm2_api.py did not list the windows within %gs; its log: %s", seconds, M.logDir))
  end)
  M.listing = listing
end

-- iTerm2's launches and quits. `itermRunning` is what the exit check reads;
-- hs.application's lookup is used only once, at load.
M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if not app or app:bundleID() ~= ITERM2 then
    return
  end
  if eventType == hs.application.watcher.launched then
    M.itermRunning = true
    log("iTerm2 launched (pid %d)", app:pid())
    if not M.task then
      start()
    end
  elseif eventType == hs.application.watcher.terminated then
    M.itermRunning = false
    log("iTerm2 quit")
    -- The script ends by itself once connected (the connection closes),
    -- but one still waiting to connect would retry for good. Forgotten
    -- here, not at its exit: an updater's relaunch can come first, and
    -- must find no script running to start a new one.
    if M.task then
      local task = M.task
      M.task = nil
      M.ready = false
      M.readyTimer:stop()
      forgetListing()
      task:terminate()
      withdrawAll("iTerm2 quit")
    end
  end
end)
M.watcher:start()

M.itermRunning = hs.application.applicationsForBundleID(ITERM2)[1] ~= nil
log("loaded: iTerm2 %s", M.itermRunning and "running" or "not running")

-- A start that fails here has alerted and logged; raising on would also
-- abort init.lua, and every module required after this one with it.
if M.itermRunning then
  local ok, err = pcall(start)
  if not ok then
    print("iterm2_api: " .. tostring(err))
  end
end

return M
