-- In iTerm2, Ctrl-M is turned into a plain Return, so it accepts the selected
-- entry in the Auto Composer's completion popup just as Return does.
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
local M = {}

local ITERM2 = "com.googlecode.iterm2"

-- Delay 0: the default 200ms between key down and up would stall the hotkey
-- callback. The explicit {} mods clear the Control the user is still holding.
local function sendReturn()
  hs.eventtap.keyStroke({}, "return", 0)
end

-- Enabled only while iTerm2 is frontmost, so Ctrl-M in other apps (Emacs
-- bindings in text fields, for one) is untouched. repeatfn keeps a held
-- Ctrl-M auto-repeating like Return.
M.hotkey = hs.hotkey.new({ "ctrl" }, "m", sendReturn, nil, sendReturn)

local function update(app)
  if app and app:bundleID() == ITERM2 then
    M.hotkey:enable()
  else
    M.hotkey:disable()
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
