-- subback.lua
--
-- LEFT seeks back. If subtitles are off, it also shows them until playback
-- is back past where LEFT was pressed, so the line just missed can be read,
-- then hides them again. If you already watch with subtitles on, LEFT is a
-- plain seek and never touches sub-visibility.
--
-- The flash ends at a position, not after a time: the seek lands on a
-- keyframe, 5 s back in one file and 15 s in another.
--
-- "sub-visibility is yes" alone cannot tell a flash from the user's own
-- subtitles, since a flash in progress also reads as yes. flash_until does:
--
--   flash_until == nil, subs off  -> seek, show, set flash_until  (start a flash)
--   flash_until ~= nil            -> seek only                    (our own flash)
--   flash_until == nil, subs on   -> seek only                    (user's subtitles)

local seek_amount = -5 -- seconds back, then on to the keyframe before that
local margin = 1 -- seconds past the press position the subs stay up

local flash_until = nil

local function end_flash()
  flash_until = nil
  mp.set_property("sub-visibility", "no")
end

-- If the user toggles subtitles off mid-flash (e.g. pressing v once to hide,
-- or twice to keep them on), the flash is over and the subtitles are theirs.
mp.observe_property("sub-visibility", "bool", function(_, visible)
  if visible == false then
    flash_until = nil
  end
end)

mp.observe_property("time-pos", "number", function(_, pos)
  if flash_until and pos and pos >= flash_until then
    end_flash()
  end
end)

-- Switching files mid-flash should not leak the temporary sub-visibility=yes
-- into the next playlist item.
mp.register_event("end-file", function()
  if flash_until then
    end_flash()
  end
end)

mp.add_key_binding("LEFT", "flash-subs-on-back", function()
  local pressed_at = mp.get_property_number("time-pos")
  mp.commandv("seek", seek_amount)

  if pressed_at == nil or flash_until or mp.get_property_bool("sub-visibility") then
    return
  end

  flash_until = pressed_at + margin
  mp.set_property("sub-visibility", "yes")
end, { repeatable = true })
