-- Usage:
--           a - replay the previous TIME_SHIFT seconds
--           A - replay the previous TIME_SHIFT seconds with subtitles
-- Status:
--    Experimental.

TIME_SHIFT=5

function replay_previous_seconds(flag)
  if flag == true
  then
    mp.set_property("sub-visibility", "yes")
    START = mp.get_next_timeout()
    if START == nil then
      START = 0
    end
    if hide_timer ~= nil then
      hide_timer:kill()
    end
    hide_timer = mp.add_timeout(START+TIME_SHIFT, replay_finished)
  end
  mp.commandv("seek", -TIME_SHIFT, "relative+exact")
end

function replay_previous_seconds_with_subtitles()
    replay_previous_seconds(true)
end

function replay_finished()
    mp.set_property("sub-visibility", "no")
    hide_timer = nil
end

function init()
    mp.add_key_binding("a", "replay-previous-sentence", replay_previous_seconds)
    mp.add_key_binding("s", "replay-previous-sentence-with-subtitles", replay_previous_seconds_with_subtitles)
end

mp.register_event("file-loaded", init)
