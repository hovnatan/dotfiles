#!/usr/bin/env python3

import i3ipc
import subprocess

i3 = i3ipc.Connection()

lays = {}
previous_focus = -1
deleted_focus = -1

def on_window_focus(i3, e):
    global previous_focus
    if previous_focus != -1 and previous_focus != deleted_focus:
        result = subprocess.run(['check_layout.sh'], stdout=subprocess.PIPE)
        if result.stdout.decode() == "us":
            lays[previous_focus] = 0
        else:
            lays[previous_focus] = 1
    current_focus = i3.get_tree().find_focused().id
    subprocess.run(["setxkbmap", "-option", ""])
    if current_focus not in lays:
        subprocess.run(["setxkbmap", "-layout", "us,am", "-variant", ",phonetic-alt", "-option", "ctrl:nocaps,grp:rctrl_switch"])
        lays[current_focus] = 0
        #print(current_focus)
    else:
        val = lays[current_focus]
        if val == 0:
            subprocess.run(["setxkbmap", "-layout", "us,am", "-variant", ",phonetic-alt", "-option", "ctrl:nocaps,grp:rctrl_switch"])
        else:
            subprocess.run(["setxkbmap", "-layout", "am,us", "-variant", "phonetic-alt,", "-option", "ctrl:nocaps,grp:rctrl_switch"])
    subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])
    previous_focus = current_focus
    #print(len(lays))

def on_window_close(i3, e):
    global deleted_focus
    current_focus = e.container.id 
    if current_focus in lays:
        del lays[current_focus]
        deleted_focus = current_focus

i3.on("window::focus", on_window_focus)
i3.on("window::close", on_window_close)

i3.main()
