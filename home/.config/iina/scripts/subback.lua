-- flash-subs-on-back.lua
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

local seek_amount = -5      -- seconds to seek back
local flash_duration = 6    -- seconds to keep subs visible

local timer = nil

mp.add_key_binding("LEFT", "flash-subs-on-back", function()
    mp.commandv("seek", seek_amount)

    -- Subtitles the user enabled are theirs: seek and leave them alone.
    if timer == nil and mp.get_property("sub-visibility") == "yes" then
        return
    end

    mp.set_property("sub-visibility", "yes")

    -- Restart the countdown, so holding LEFT keeps the subs up rather than
    -- letting the first press hide them mid-scrub.
    if timer then
        timer:kill()
    end
    timer = mp.add_timeout(flash_duration, function()
        mp.set_property("sub-visibility", "no")
        timer = nil
    end)
end)
