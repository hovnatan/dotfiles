-- subback.lua
--
-- LEFT seeks back a few seconds. If subtitles are off, it also flashes them
-- on for a moment so you can read the line you just missed, then hides them
-- again. If you already watch with subtitles on, LEFT is a plain seek and
-- never touches sub-visibility.
--
-- "sub-visibility is yes" alone cannot tell those cases apart, since a flash
-- in progress also reads as yes. The live timer is the discriminator:
--
--   timer == nil, subs off  -> seek, show, arm timer   (start a flash)
--   timer ~= nil            -> seek, re-arm timer      (extend our own flash)
--   timer == nil, subs on   -> seek only               (user's subtitles)

local seek_amount = -5 -- seconds to seek back
local flash_duration = 6 -- seconds to keep subs visible

local timer = nil

local function cancel_timer()
  if timer then
    timer:kill()
    timer = nil
  end
end

-- If the user toggles subtitles off mid-flash (e.g. pressing v once to hide,
-- or twice to keep them on), drop our timer so it never fights them.
mp.observe_property("sub-visibility", "bool", function(_, visible)
  if timer and visible == false then
    cancel_timer()
  end
end)

-- Freeze the flash countdown while paused so a line stays up while reading it.
mp.observe_property("pause", "bool", function(_, paused)
  if not timer then
    return
  end
  if paused then
    timer:stop()
  else
    timer:resume()
  end
end)

-- Switching files mid-flash should not leak the temporary sub-visibility=yes
-- into the next playlist item or hide its subtitles seconds later.
mp.register_event("end-file", function()
  if timer then
    cancel_timer()
    mp.set_property("sub-visibility", "no")
  end
end)

mp.add_key_binding("LEFT", "flash-subs-on-back", function()
  mp.commandv("seek", seek_amount, "exact")

  -- Subtitles the user enabled are theirs: seek and leave them alone.
  if timer == nil and mp.get_property("sub-visibility") == "yes" then
    return
  end

  mp.set_property("sub-visibility", "yes")

  -- Restart the countdown, so holding LEFT keeps the subs up rather than
  -- letting the first press hide them mid-scrub. Start paused if playback is.
  cancel_timer()
  timer = mp.add_timeout(flash_duration, function()
    timer = nil
    mp.set_property("sub-visibility", "no")
  end, mp.get_property_bool("pause"))
end, { repeatable = true })
