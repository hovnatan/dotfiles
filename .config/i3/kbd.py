#!/usr/bin/env python3

import i3ipc
import subprocess

i3 = i3ipc.Connection()

lays = {}
previous_focus = -1

def on_window_focus(i3, e):
    global previous_focus
    if previous_focus != -1:
        result = subprocess.run(['xkblayout-state', 'print', '%s'], stdout=subprocess.PIPE)
        if result.stdout.decode() == "us":
            lays[previous_focus] = 0
        else:
            lays[previous_focus] = 1
    current_focus = i3.get_tree().find_focused().id
    if current_focus not in lays:
        subprocess.run(["setxkbmap", "us"])
        lays[current_focus] = 0
    else:
        val = lays[current_focus]
        if val == 0:
            subprocess.run(["setxkbmap", "us"])
        else:
            subprocess.run(["setxkbmap", "-layout", "am", "-variant", "phonetic-alt"])
        subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])

    previous_focus = current_focus

def on_window_close(i3, e):
    current_focus = e.container.id 
    del lays[current_focus]

i3.on("window::focus", on_window_focus)
i3.on("window::close", on_window_close)

i3.main()
