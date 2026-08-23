-- flash-subs-on-back.lua
local seek_amount = -5      -- seconds to seek back
local flash_duration = 6    -- seconds to keep subs visible

local timer = nil

mp.add_key_binding("LEFT", "flash-subs-on-back", function()
    mp.commandv("seek", seek_amount)
    mp.set_property("sub-visibility", "yes")

    if timer then
        timer:kill()
    end
    timer = mp.add_timeout(flash_duration, function()
        mp.set_property("sub-visibility", "no")
        timer = nil
    end)
end)
