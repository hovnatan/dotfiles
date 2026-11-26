-- LEFT goes back to the start of the subtitle line on screen, or of the
-- previous line when that line has only just begun or no line is on screen,
-- so a second press steps back a line. It lands a little before the start: a
-- line's timing is rarely exact, and speech can begin before its text. It
-- leaves sub-visibility alone.
--
-- Shift+LEFT goes back the same way. If subtitles are off, it also shows them
-- until the line on screen when it was pressed has ended (between two lines:
-- until playback is back where it was pressed), so the line just missed can
-- be read, then hides them again. If you already watch with subtitles on, it
-- is LEFT and never touches sub-visibility.
--
-- Where there is no line to go back to (no subtitle track, before the first
-- line, a track inside the file whose earlier lines mpv has not read yet),
-- both seek back by time.
--
-- No keys here: input.conf binds both by name.

local fallback_seek = -5 -- seconds, where there is no line to go back to
local lead_in = 1.5 -- seconds before a line's start to land
local previous_line_within = 2 -- seconds into a line a press goes to the line before

-- Where the flash in progress ends; nil when there is none. sub-visibility
-- cannot stand in for it: a flash reads "yes" just as the user's own
-- subtitles do. waiting_for_seek suppresses time-pos checks while a queued
-- seek is still flushing/decoding, so pre-seek timestamps cannot end the flash
-- early (e.g. over high-latency SMB or on 4K HEVC).
local flash_until = nil
local waiting_for_seek = false

local function end_flash()
  flash_until = nil
  waiting_for_seek = false
  mp.set_property("sub-visibility", "no")
end

-- If the user toggles subtitles off mid-flash (e.g. pressing v once to hide,
-- or twice to keep them on), the flash is over and the subtitles are theirs.
mp.observe_property("sub-visibility", "bool", function(_, visible)
  if visible == false then
    flash_until = nil
    waiting_for_seek = false
  end
end)

mp.register_event("playback-restart", function()
  waiting_for_seek = false
end)

mp.observe_property("time-pos", "number", function(_, pos)
  if flash_until and not waiting_for_seek and pos and pos >= flash_until then
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

-- sub-start and sub-end are on the subtitle track's clock, time-pos on the
-- video's: sub-delay and sub-speed lie between the two.
local function line_on_screen()
  local speed = mp.get_property_number("sub-speed") or 1
  local delay = mp.get_property_number("sub-delay") or 0
  local line_start = mp.get_property_number("sub-start")
  local line_end = mp.get_property_number("sub-end")
  return line_start and line_start * speed + delay, line_end and line_end * speed + delay
end

local function back_a_line()
  local pressed_at = mp.get_property_number("time-pos")
  if pressed_at == nil then
    return
  end

  local line_start, line_end = line_on_screen()
  local previous = line_start == nil or pressed_at - line_start <= previous_line_within
  if flash_until then
    waiting_for_seek = true
  end
  -- One command, so all three are queued before any runs: sub-seek's seek to
  -- a line replaces the queued seek by time, which stands when sub-seek finds
  -- no line, and the lead-in is added to whichever is queued (relative+exact
  -- keeps sub-seek's precision instead of snapping to a keyframe).
  local cmd = ("osd-auto seek %g; osd-auto sub-seek %d; osd-auto seek %g relative+exact"):format(
    fallback_seek + lead_in,
    previous and -1 or 0,
    -lead_in
  )
  mp.command(cmd)
  return pressed_at, line_end
end

mp.add_key_binding(nil, "back-a-subtitle-line", back_a_line, { repeatable = true })

mp.add_key_binding(nil, "flash-subs-on-back", function()
  local pressed_at, line_end = back_a_line()
  if pressed_at == nil or flash_until or mp.get_property_bool("sub-visibility") then
    return
  end

  waiting_for_seek = true
  flash_until = math.max(line_end or 0, pressed_at)
  mp.set_property("sub-visibility", "yes")
end, { repeatable = true })
