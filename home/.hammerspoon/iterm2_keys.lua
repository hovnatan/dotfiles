-- Key rewrites in iTerm2, through one key-down event tap that runs only while
-- iTerm2 is frontmost, so the same keys in other apps (Emacs bindings in text
-- fields, for one) are untouched:
--
--   app watcher --(iTerm2 frontmost?)--> start / stop the tap
--
--   key down, Control only
--     Ctrl-M --> Return
--     Ctrl-U / Ctrl-D --> focus on a terminal view, on the main screen?
--        no  --> the key, unchanged (a full-screen program, the composer,
--                the find bar)
--        yes --> Ctrl-U: Shift-PageUp, iTerm2 scrolls up one page
--                Ctrl-D: scrolled back?  yes --> Shift-PageDown
--                                        no  --> Ctrl-D, unchanged (EOF)
--     anything else --> unchanged
--
--   key down, Command only
--     Cmd-T --> focus on a terminal view, its foreground job ssh, and the
--               login (`ssh <options> <destination>`) re-parsed safely?
--        no  --> the key, unchanged (iTerm2's own New Tab)
--        yes --> swallowed; right after, a new tab in that same window
--                types just that login into its local shell
--
-- A key the tap leaves alone goes on as the real event; a rewritten one is
-- swallowed and replaced by a synthetic keystroke or an iTerm2 command.
local M = {}

local sshCommand = require("ssh_command")

local ITERM2 = "com.googlecode.iterm2"
local KEY = hs.keycodes.map

-- Each Ctrl-U / Ctrl-D / Cmd-T decision and every error is logged (event_log.lua),
-- to the file only: a line per keypress would crowd the Console. E.g.
--   2026-09-29T20:10:02.114Z Ctrl-U: pass through (full-screen program, alt-screen check 18 ms)
local log
log, M.logDir = require("event_log").new("iterm2_keys", { console = false })

local function fail(msg)
  log("ERROR %s", msg)
  error("iterm2_keys: " .. msg)
end
local AUTOREPEAT = hs.eventtap.event.properties.keyboardEventAutorepeat

-- An AppleScript to iTerm2, in process, and its result; about 17ms, an
-- Apple Event round trip. A failure is a broken setup (no Automation
-- permission for Hammerspoon to control iTerm2), so raise rather than guess.
-- It runs on Hammerspoon's main thread, inside the key tap, so the wait is
-- capped at 1s: a beachballing iTerm2 would otherwise hold every hotkey for
-- the default 2 minutes (error -1712, "timed out", then raises).
local function iterm2(script, what)
  local ok, value, raw = hs.osascript.applescript("with timeout of 1 second\n" .. script .. "\nend timeout")
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

-- Ctrl-M: in iTerm2, Ctrl-M is turned into a plain Return, so it accepts the
-- selected entry in the Auto Composer's completion popup just as Return does.
--
-- The popup (iTerm2 sources/Composer/ComposerTextView.swift) accepts only a
-- "\r" keypress with no modifiers held; Ctrl-M is "\r" with Control held, so
-- it falls through and inserts a line break instead. iTerm2's own key
-- mappings act on the terminal session, not on the composer's text field,
-- so the fix has to rewrite the key before iTerm2 sees it.
--
-- In the terminal itself this changes nothing, since both keys send CR.
-- The exception is a program that asks for the kitty keyboard protocol
-- (nvim does): it now receives <CR> for Ctrl-M, never <C-m>.
--
-- Delay 0: the default 200ms between key down and up would stall the tap
-- callback. The explicit mods replace the Control the user is still holding.
local function sendReturn()
  hs.eventtap.keyStroke({}, "return", 0)
end

-- Ctrl-U / Ctrl-D: on the main screen (a shell, Claude Code), page iTerm2's
-- scrollback up and down; a full-screen program (onAlternateScreen) gets
-- them and pages itself, tmux into its copy mode (~/.tmux.conf). Ctrl-D
-- scrolls only while the view is scrolled back, so at the bottom it is
-- Ctrl-D again: EOF still exits a shell.
--
-- Shift-PageUp / Shift-PageDown are iTerm2's own "Scroll One Page Up/Down"
-- keys (GlobalKeyMap, scripts/setup_user_symlinks.sh). The scroll area's
-- AXScrollUpByPage / AXScrollDownByPage would skip that dependency, but
-- iTerm2 3.7.3 gets them wrong: up does nothing, down scrolls up.
local function scrollUp()
  hs.eventtap.keyStroke({ "shift" }, "pageup", 0)
end

local function scrollDown()
  hs.eventtap.keyStroke({ "shift" }, "pagedown", 0)
end

-- Whether a full-screen program owns the tab: iTerm2's own
-- showingAlternateScreen, 1 while a program has switched to the alternate
-- screen (nvim, less, htop, a tmux client; `less -X` and fzf --height stay
-- on the main screen, so they do not count). iTerm2 tracks it from the
-- terminal stream, so it holds over ssh and needs no report from the shell,
-- and a tmux detach clears it at once. The one miss is a dropped ssh
-- connection, which never switches back: it stays 1 until `reset`.
local ALT_SCREEN = [[
tell application "iTerm2" to tell current session of current window
  return variable named "showingAlternateScreen"
end tell
]]

local function onAlternateScreen()
  -- The ~17ms Apple Event, so it runs last; it also fails with no window.
  local value = iterm2(ALT_SCREEN, "reading iTerm2 showingAlternateScreen")
  -- Always "0" or "1"; anything else (nil when iTerm2 renamed or dropped the
  -- variable) would otherwise read as "main screen" and silently take every
  -- full-screen program's Ctrl-U.
  if value == "1" then
    return true
  elseif value == "0" then
    return false
  end
  fail("iTerm2 showingAlternateScreen is " .. hs.inspect(value) .. ', not "0" or "1"')
end

-- The focused session's terminal view, read through the accessibility tree:
--
--   AXScrollArea                    holds AXVerticalScrollBar, value 0..1
--     AXTextArea "shell"            the terminal; keyboard focus when typing
--
-- nil when focus is elsewhere in iTerm2 (the composer, the find bar, Settings).
local function focusedTerminal()
  local app = hs.axuielement.applicationElement(hs.application.frontmostApplication())
  local focused = app:attributeValue("AXFocusedUIElement")
  if
    focused
    and focused:attributeValue("AXRole") == "AXTextArea"
    and focused:attributeValue("AXDescription") == "shell"
  then
    return focused
  end
end

-- Whether the view is scrolled back, from the scroll bar (iTerm2 3.7.3):
--   content taller than the view   enabled, value exactly 1 at the bottom,
--                                  below 1 once scrolled back
--   content fits (nothing to       disabled, value 0: that is the bottom,
--   scroll: a fresh ssh session)   not scrolled to the top
-- Reading 0 as "scrolled back" there turned every Ctrl-D into a no-op
-- Shift-PageDown, so EOF never reached a fresh remote shell. A terminal view
-- outside a scroll area with a scroll bar, or a bar without a boolean
-- AXEnabled, means iTerm2's view layout changed under us: raise, since
-- guessing "at the bottom" would turn a scroll into EOF.
local function scrolledBack(terminal)
  local area = terminal:attributeValue("AXParent")
  local bar = area and area:attributeValue("AXVerticalScrollBar")
  if not bar then
    fail(
      "iTerm2's terminal view has no AXScrollArea parent with a vertical "
        .. "scroll bar; its accessibility layout changed, see focusedTerminal"
    )
  end
  local enabled = bar:attributeValue("AXEnabled")
  if type(enabled) ~= "boolean" then
    fail("iTerm2's scroll bar AXEnabled is " .. hs.inspect(enabled) .. ", not a boolean; see scrolledBack")
  end
  return enabled and bar:attributeValue("AXValue") < 1
end

-- Cmd-T in an ssh tab: open the new tab on the same machine. The test is
-- the local foreground job (jobName, commandLine), the process iTerm2's own
-- pty sees, so it holds whatever runs on the far side (a remote tmux, a
-- nested ssh: that one reopens the first hop). Only the login is replayed,
-- `ssh <options> <destination>` from ssh_command.lua: a remote command
-- (`ssh vm ./deploy.sh`), a forward or -N never runs twice, and a command
-- line it cannot re-parse safely gets iTerm2's plain New Tab instead.
-- ControlMaster in ~/.ssh/config makes the second connection instant.
--
-- The new tab goes through the shell, not a tab "command", so exiting ssh
-- leaves a local shell, as if the command had been typed by hand. It uses
-- the default profile, as iTerm2's New Tab does.
--
-- Two steps, so Hammerspoon's main thread (the tap, every hotkey) never
-- waits on the tab:
--   in the callback  read window id, jobName, commandLine (~17ms, one
--                    Apple Event); ssh? swallow the key
--   own process      osascript creates the tab in the window with that id
--                    (~300ms) and types the command, both passed as argv,
--                    so the command needs no AppleScript quoting
-- Pinning the window id means the tab lands in the window the key was
-- pressed in even if focus moves in between.
local CURRENT_JOB = [[
tell application "iTerm2"
  set w to current window
  if w is missing value then return {}
  tell current session of w
    return {id of w, variable named "jobName", variable named "commandLine"}
  end tell
end tell
]]

local OPEN_TAB = [[
on run argv
  tell application "iTerm2"
    tell (first window whose id is (item 1 of argv as integer)) to set t to (create tab with default profile)
    tell current session of t to write text (item 2 of argv)
  end tell
end run
]]

-- Running osascript tasks, held so none is garbage-collected mid-run.
local openTasks = {}

local function openSshTab(windowId, command)
  local task
  task = hs.task.new("/usr/bin/osascript", function(exitCode, _, stderr)
    openTasks[task] = nil
    if exitCode ~= 0 then
      fail(string.format("osascript opening `%s` in window %d exited %d: %s", command, windowId, exitCode, stderr))
    end
    log("Cmd-T: opened `%s` in a new tab of window %d", command, windowId)
  end, { "-e", OPEN_TAB, tostring(windowId), command })
  openTasks[task] = true
  task:start()
end

-- Whether Cmd-T was taken: true once the ssh tab is on its way, false to let
-- iTerm2's New Tab run.
local function sshNewTab()
  -- Focus outside a terminal view (Settings, the composer, the find bar):
  -- `current window` below would be the last terminal window, maybe one in
  -- the background, so leave the key to iTerm2.
  if not focusedTerminal() then
    log("Cmd-T: pass through (focus not on a terminal view)")
    return false
  end
  local result = iterm2(CURRENT_JOB, "reading iTerm2's current job")
  -- No window (all closed): pass, so Cmd-T still opens one.
  if #result == 0 then
    log("Cmd-T: pass through (no iTerm2 window)")
    return false
  end
  local windowId, job, command = table.unpack(result)
  -- Both are set for every live session (a fresh tab reports its shell);
  -- missing means iTerm2 renamed or dropped them, which would otherwise read
  -- as "not ssh" and silently turn the feature off. The test is jobName, the
  -- process name, so `/usr/bin/ssh vm` counts too.
  if type(job) ~= "string" or type(command) ~= "string" then
    fail("iTerm2 jobName / commandLine are " .. hs.inspect(result) .. ", not strings; see sshNewTab")
  end
  if job ~= "ssh" then
    log("Cmd-T: pass through (foreground job %s)", job)
    return false
  end
  -- The log gets the replay only, never the dropped remote command, which
  -- may carry a secret (`ssh vm env TOKEN=... ./job`).
  local replay, why = sshCommand.interactive(command)
  if not replay then
    log("Cmd-T: pass through (ssh command line not replayable: %s)", why)
    return false
  end
  openSshTab(windowId, replay)
  return true
end

-- What a press of Control plus keyCode does: a rewrite function, or nil to
-- let the key through, and why (for the log). Checks run cheapest first
-- (~0.3ms accessibility reads, then the ~17ms AppleScript), so a Ctrl-D at
-- the bottom never pays for it.
local function decide(keyCode)
  if keyCode == KEY.m then
    return sendReturn
  end
  local terminal = focusedTerminal()
  if not terminal then
    return nil, "focus not on a terminal view"
  end
  if keyCode == KEY.d and not scrolledBack(terminal) then
    return nil, "at the bottom"
  end
  local started = hs.timer.absoluteTime()
  local alternate = onAlternateScreen()
  local ms = (hs.timer.absoluteTime() - started) / 1e6
  if alternate then
    return nil, string.format("full-screen program, alt-screen check %.0f ms", ms)
  end
  return keyCode == KEY.u and scrollUp or scrollDown, string.format("main screen, alt-screen check %.0f ms", ms)
end

-- A held key repeats what its first press decided, without asking again:
-- repeats of a pass-through pass through (nvim paging down), repeats of a
-- scroll scroll. A held Ctrl-D thus stops at the bottom, where Shift-PageDown
-- does nothing, and never overshoots into an EOF that closes the shell.
local held = { keyCode = nil, action = nil }

-- Same for Cmd-T, by the first press's answer: a held Cmd-T in an ssh tab
-- opens one tab, not one per repeat; elsewhere iTerm2's own repeat runs.
-- Reset before each first press, so a check that raises leaves "not taken"
-- for its repeats rather than the previous press's answer.
local cmdTTaken = false

local function onKeyDown(event)
  local keyCode = event:getKeyCode()
  if keyCode == KEY.t and event:getFlags():containExactly({ "cmd" }) then
    if event:getProperty(AUTOREPEAT) == 0 then
      cmdTTaken = false
      cmdTTaken = sshNewTab()
    end
    return cmdTTaken
  end
  if
    (keyCode ~= KEY.m and keyCode ~= KEY.u and keyCode ~= KEY.d) or not event:getFlags():containExactly({ "ctrl" })
  then
    return false
  end
  if event:getProperty(AUTOREPEAT) == 0 or held.keyCode ~= keyCode then
    local reason
    held.keyCode, held.action, reason = keyCode, decide(keyCode)
    if keyCode ~= KEY.m then
      local key = keyCode == KEY.u and "Ctrl-U" or "Ctrl-D"
      local what = held.action == scrollUp and "scroll up"
        or held.action == scrollDown and "scroll down"
        or "pass through"
      log("%s: %s (%s)", key, what, reason)
    end
  end
  if not held.action then
    return false
  end
  held.action()
  return true
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, onKeyDown)

local function update(app)
  if app and app:bundleID() == ITERM2 then
    M.tap:start()
  else
    M.tap:stop()
  end
end

-- Kept in the module table so the watcher is not garbage-collected.
M.watcher = hs.application.watcher.new(function(_, eventType, app)
  if eventType == hs.application.watcher.activated then
    update(app)
  end
end)
M.watcher:start()

-- Apply on load in case iTerm2 is already frontmost.
update(hs.application.frontmostApplication())

return M
