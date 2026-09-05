-- timeleft.lua
--
-- One key answers "how much of the movie is left?": flashes the remaining
-- playtime on the OSD together with the wall-clock time playback will end,
-- so you can decide whether to keep watching without doing the arithmetic.
--
--     41:17 left, ends at 23:52
--
-- IINA does not forward unbound keys to mpv, so the key below only matters
-- for plain mpv. Under IINA the key comes from its own key-binding conf
-- (Preferences > Key Bindings), which needs the line
--
--     o script-binding show-time-left

local key = "o"
local osd_duration = 3   -- seconds the message stays up

-- 5025s -> "1:23:45"; 2477s -> "41:17". Hours are dropped when zero so the
-- common under-an-hour case reads at a glance.
local function fmt_hms(secs)
    secs = math.floor(secs + 0.5)
    local h = math.floor(secs / 3600)
    local m = math.floor(secs % 3600 / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

mp.add_key_binding(key, "show-time-left", function()
    -- playtime-remaining, not time-remaining: it divides by the playback
    -- speed, so at 1.5x it is the wall-clock answer.
    local remaining = mp.get_property_number("playtime-remaining")

    -- Live streams and not-yet-loaded files have no duration; say so rather
    -- than flashing nothing.
    if remaining == nil then
        mp.osd_message("Time left unknown: no duration", osd_duration)
        return
    end

    local ends_at = os.date("%H:%M", os.time() + math.floor(remaining + 0.5))
    mp.osd_message(string.format("%s left, ends at %s", fmt_hms(remaining), ends_at),
                   osd_duration)
end)
