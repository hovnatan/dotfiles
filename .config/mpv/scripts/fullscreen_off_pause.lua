function on_pause_change(name, value)
    if value == true then
        mp.set_property("fullscreen", "no")
    end
end
mp.observe_property("pause", "bool", on_pause_change)

function something_handler()
    print("the key was pressed")
    mp.command("osd-msg-bar seek 32")
end
mp.add_key_binding("x", "something", something_handler)

seconds = 0
timer = mp.add_periodic_timer(1, function()
--    print("called every second")
-- stop it after 10 seconds
    seconds = seconds + 1
    if seconds >= 10 then
        timer:kill()
    end
end)
