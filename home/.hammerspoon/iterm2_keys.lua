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
-- A key the tap leaves alone goes on as the real event; a rewritten one is
-- swallowed and replaced by a synthetic keystroke.
local M = {}

local ITERM2 = "com.googlecode.iterm2"
local KEY = hs.keycodes.map
local AUTOREPEAT = hs.eventtap.event.properties.keyboardEventAutorepeat

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
  -- About 17ms per call, an Apple Event round trip, so it runs last. A
  -- failure is a broken setup (no Automation permission for Hammerspoon to
  -- control iTerm2, no window), so raise rather than guess where the key goes.
  local ok, value, raw = hs.osascript.applescript(ALT_SCREEN)
  if not ok then
    error(
      "iterm2_keys: reading iTerm2 showingAlternateScreen failed (allow Hammerspoon "
        .. "to control iTerm2 in System Settings > Privacy & Security > Automation): "
        .. hs.inspect(raw)
    )
  end
  -- Always "0" or "1"; anything else (nil when iTerm2 renamed or dropped the
  -- variable) would otherwise read as "main screen" and silently take every
  -- full-screen program's Ctrl-U.
  if value == "1" then
    return true
  elseif value == "0" then
    return false
  end
  error("iterm2_keys: iTerm2 showingAlternateScreen is " .. hs.inspect(value) .. ', not "0" or "1"')
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

-- The scroll bar's value is exactly 1 at the bottom, with a long scrollback
-- or none (checked on iTerm2 3.7.3), and below 1 once scrolled back. A
-- terminal view outside a scroll area with a scroll bar means iTerm2's view
-- layout changed under us: raise, since guessing "at the bottom" would turn
-- a scroll into EOF.
local function scrolledBack(terminal)
  local area = terminal:attributeValue("AXParent")
  local bar = area and area:attributeValue("AXVerticalScrollBar")
  if not bar then
    error(
      "iterm2_keys: iTerm2's terminal view has no AXScrollArea parent with a vertical "
        .. "scroll bar; its accessibility layout changed, see focusedTerminal"
    )
  end
  return bar:attributeValue("AXValue") < 1
end

-- What a press of Control plus keyCode does: a rewrite function, or nil to
-- let the key through. Checks run cheapest first (~0.3ms accessibility reads,
-- then the ~17ms AppleScript), so a Ctrl-D at the bottom never pays for it.
local function decide(keyCode)
  if keyCode == KEY.m then
    return sendReturn
  end
  local terminal = focusedTerminal()
  if not terminal then
    return nil
  end
  if keyCode == KEY.u then
    return not onAlternateScreen() and scrollUp or nil
  end
  return scrolledBack(terminal) and not onAlternateScreen() and scrollDown or nil
end

-- A held key repeats what its first press decided, without asking again:
-- repeats of a pass-through pass through (nvim paging down), repeats of a
-- scroll scroll. A held Ctrl-D thus stops at the bottom, where Shift-PageDown
-- does nothing, and never overshoots into an EOF that closes the shell.
local held = { keyCode = nil, action = nil }

local function onKeyDown(event)
  local keyCode = event:getKeyCode()
  if
    (keyCode ~= KEY.m and keyCode ~= KEY.u and keyCode ~= KEY.d) or not event:getFlags():containExactly({ "ctrl" })
  then
    return false
  end
  if event:getProperty(AUTOREPEAT) == 0 or held.keyCode ~= keyCode then
    held.keyCode, held.action = keyCode, decide(keyCode)
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
