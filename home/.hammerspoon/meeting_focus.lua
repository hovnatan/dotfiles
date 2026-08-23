-- Turn on Do Not Disturb while in a meeting, off when it ends.
--
-- Detection: any real audio input in use. Meet/Zoom/Slack hold the mic open
-- for the whole call (muting is done in software), so this covers audio-only
-- and camera-off calls without flapping on mute. Short bursts (push-to-talk
-- voice input, dictation) are filtered by DEBOUNCE.
--
-- macOS has no public Focus API, so toggling goes through the Shortcuts CLI;
-- create "Focus On" / "Focus Off" shortcuts with a Set Focus action.
local M = {}

local POLL_INTERVAL = 5 -- seconds
local DEBOUNCE = 25 -- continuous mic use before Focus turns on
local IGNORED_INPUTS = { ["Microsoft Teams Audio"] = true } -- virtual device

local focusIsOurs = false
local micSince = nil

local function micInUse()
  for _, dev in ipairs(hs.audiodevice.allInputDevices()) do
    if not IGNORED_INPUTS[dev:name()] and dev:inUse() then return true end
  end
  return false
end

local function runShortcut(name)
  hs.task.new("/usr/bin/shortcuts", nil, { "run", name }):start()
end

local function tick()
  if micInUse() then
    micSince = micSince or os.time()
    if not focusIsOurs and os.time() - micSince >= DEBOUNCE then
      focusIsOurs = true
      runShortcut("Focus On")
    end
  else
    micSince = nil
    -- Only clear Focus we turned on, so a manually set Focus survives.
    if focusIsOurs then
      focusIsOurs = false
      runShortcut("Focus Off")
    end
  end
end

M.timer = hs.timer.doEvery(POLL_INTERVAL, tick)

return M
