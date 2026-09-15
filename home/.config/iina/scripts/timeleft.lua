-- timeleft.lua
--
-- One key answers "how much of the movie is left?": flashes the remaining
-- playtime top-right together with the wall-clock time playback will end,
-- so you can decide whether to keep watching without doing the arithmetic.
--
--     41:17 left, ends at 23:52
--
-- Two bindings: show-time-left is the message on its own, and
-- pause-with-time-left toggles pause and shows it only when that lands on
-- paused, so the play/pause key doubles as the "how much is left" key:
-- pausing to check the clock is what you were going to do anyway.
--
-- IINA does not forward unbound keys to mpv, so the keys below only matter
-- for plain mpv. Under IINA the keys come from its own key-binding conf
-- (Preferences > Key Bindings), which needs the lines
--
--     o script-binding show-time-left
--     SPACE script-binding pause-with-time-left

local key = "o"
local osd_duration = 3   -- seconds the message stays up

-- Drawn as an ASS overlay pinned top-right ({\an9}) rather than through
-- mp.osd_message: that one lands at mpv's OSD position, top-left, which is
-- where IINA draws its own "Pause" badge, and the two would overlap on
-- every pause.
local overlay = mp.create_osd_overlay("ass-events")
local hide_timer = nil

local function flash(text)
    overlay.data = "{\\an9}" .. text
    overlay:update()

    -- A second press restarts the countdown instead of leaving the first
    -- timer to hide a message that was just refreshed.
    if hide_timer then
        hide_timer:kill()
    end
    hide_timer = mp.add_timeout(osd_duration, function()
        overlay:remove()
        hide_timer = nil
    end)
end

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

local function show_time_left()
    -- playtime-remaining, not time-remaining: it divides by the playback
    -- speed, so at 1.5x it is the wall-clock answer.
    local remaining = mp.get_property_number("playtime-remaining")

    -- Live streams and not-yet-loaded files have no duration; say so rather
    -- than flashing nothing.
    if remaining == nil then
        flash("Time left unknown: no duration")
        return
    end

    local ends_at = os.date("%H:%M", os.time() + math.floor(remaining + 0.5))
    flash(string.format("%s left, ends at %s", fmt_hms(remaining), ends_at))
end

mp.add_key_binding(key, "show-time-left", show_time_left)

mp.add_key_binding("SPACE", "pause-with-time-left", function()
    mp.commandv("cycle", "pause")
    -- Only on the way into pause: resuming is a decision already made, and
    -- a message over the first seconds of playback is just noise.
    if mp.get_property_bool("pause") then
        show_time_left()
    end
end)
