-- Key rewrites that apply only while iTerm2 is frontmost:
--
--   app watcher --(iTerm2 frontmost?)--> enable / disable both hotkeys
--
--   Ctrl-M --> Return
--   Ctrl-U --> read iTerm2 user.at_prompt of the current session
--                1     --> Shift-PageUp: iTerm2 scrolls up one page
--                other --> Ctrl-U, unchanged, to the program
--
-- Only while iTerm2 is frontmost, so Ctrl-M and Ctrl-U in other apps (Emacs
-- bindings in text fields, for one) are untouched.
local M = {}

local ITERM2 = "com.googlecode.iterm2"

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
-- Delay 0: the default 200ms between key down and up would stall the hotkey
-- callback. The explicit {} mods clear the Control the user is still holding.
local function sendReturn()
  hs.eventtap.keyStroke({}, "return", 0)
end

-- repeatfn keeps a held Ctrl-M auto-repeating like Return.
M.ctrlM = hs.hotkey.new({ "ctrl" }, "m", sendReturn, nil, sendReturn)

-- Ctrl-U: at a shell prompt, scroll iTerm2 up a page; anywhere else, Ctrl-U
-- as usual. Mirrors C-u in ~/.tmux.conf, which enters copy mode unless a
-- full-screen program runs, so the key means "scroll back" in and out of
-- tmux. fish reports the prompt as the user variable at_prompt
-- (~/.config/fish/functions/iterm2_report_prompt.fish): 1 at its prompt, 0
-- while a command (nvim, tmux, ssh, ...) runs. It is unset in a tab whose
-- shell never reported, e.g. bash, and Ctrl-U then passes through.
--
-- Shift-PageUp is iTerm2's own "Scroll One Page Up" key (GlobalKeyMap,
-- scripts/setup_user_symlinks.sh).
local AT_PROMPT = [[
tell application "iTerm2" to tell current session of current window
  return variable named "user.at_prompt"
end tell
]]

local function atPrompt()
  -- About 10ms per call. A failure is a broken setup (no Automation
  -- permission for Hammerspoon to control iTerm2, no window), so raise
  -- rather than guess which way the key should go.
  local ok, value, raw = hs.osascript.applescript(AT_PROMPT)
  if not ok then
    error(
      "iterm2_keys: reading iTerm2 user.at_prompt failed (allow Hammerspoon to control "
        .. "iTerm2 in System Settings > Privacy & Security > Automation): "
        .. hs.inspect(raw)
    )
  end
  return value == "1"
end

local function ctrlU()
  if atPrompt() then
    hs.eventtap.keyStroke({ "shift" }, "pageup", 0)
  else
    -- The hotkey would catch its own synthetic Ctrl-U, so step aside for it.
    M.ctrlU:disable()
    hs.eventtap.keyStroke({ "ctrl" }, "u", 0)
    M.ctrlU:enable()
  end
end

M.ctrlU = hs.hotkey.new({ "ctrl" }, "u", ctrlU, nil, ctrlU)

local function update(app)
  local inITerm2 = app ~= nil and app:bundleID() == ITERM2
  for _, hotkey in ipairs({ M.ctrlM, M.ctrlU }) do
    if inITerm2 then
      hotkey:enable()
    else
      hotkey:disable()
    end
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
