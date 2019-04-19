#!/usr/bin/env python3

import i3ipc
import subprocess

debug = False

i3 = i3ipc.Connection()

lays = {}
previous_focus = -1
deleted_focus = -1

def on_window_focus(i3, e):
    global previous_focus
    if previous_focus != -1 and previous_focus != deleted_focus:
        if debug:
            print("Previous focus found.")
        result = subprocess.run(['check_layout.sh'], stdout=subprocess.PIPE)
        if debug:
            print(f"Current layout {result}.")
        if result.stdout.decode() == "us":
            lays[previous_focus] = 0
        else:
            lays[previous_focus] = 1
    else:
        if debug:
            print("Previous focus not found.")
    current_focus = i3.get_tree().find_focused().id
    subprocess.run(["setxkbmap", "-option", ""])
    if current_focus not in lays:
        if debug:
            print(f"{current_focus} not found setting to us.")
        subprocess.run(["setxkbmap", "-layout", "us,am", "-variant", ",phonetic-alt", "-option", "ctrl:nocaps,grp:rctrl_switch"])
        lays[current_focus] = 0
        #print(current_focus)
    else:
        if debug:
            print(f"{current_focus} found.")
        val = lays[current_focus]
        if val == 0:
            subprocess.run(["setxkbmap", "-layout", "us,am", "-variant", ",phonetic-alt", "-option", "ctrl:nocaps,grp:rctrl_switch"])
            if debug:
                print(f"{current_focus} setting to us.")
        else:
            subprocess.run(["setxkbmap", "-layout", "am,us", "-variant", "phonetic-alt,", "-option", "ctrl:nocaps,grp:rctrl_switch"])
            if debug:
                print(f"{current_focus} setting to am")
    subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])
    previous_focus = current_focus

def on_window_close(i3, e):
    global deleted_focus
    current_focus = e.container.id 
    if current_focus in lays:
        del lays[current_focus]
        deleted_focus = current_focus

i3.on("window::focus", on_window_focus)
i3.on("window::close", on_window_close)

i3.main()
