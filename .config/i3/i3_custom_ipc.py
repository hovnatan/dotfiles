#!/usr/bin/env python3

import subprocess
import i3ipc
import signal
from threading import Thread, Lock

mutex = Lock()


def handle_pdb(sig, frame):
    import pdb
    pdb.Pdb().set_trace(frame)


DEBUG = False

i3 = i3ipc.Connection()

lays = {}
previous_focus = -1
deleted_focus = -1


def on_window_focus(i3, e):
    with mutex:
        if DEBUG:
            f.write(f"Len {len(lays)}\n".encode())
            f.write(f"{lays}\n".encode())
        global previous_focus
        if previous_focus not in (-1, deleted_focus):
            if DEBUG:
                f.write("Previous focus found.\n".encode())
            result = subprocess.run(['check_layout.sh'], stdout=subprocess.PIPE)
            if DEBUG:
                f.write(f"Current layout {result}.\n".encode())
            if result.stdout.decode() == "am":
                lays[previous_focus] = 1
            else:
                lays[previous_focus] = 0
        else:
            if DEBUG:
                f.write("Previous focus not found.\n".encode())
        current_focus = i3.get_tree().find_focused().id
        subprocess.run(["setxkbmap", "-option", ""])
        if current_focus not in lays:
            if DEBUG:
                f.write(f"{current_focus} not found setting to us.\n".encode())
            subprocess.run(
                [
                    "setxkbmap", "-layout", "us,am", "-variant",
                    ",phonetic-alt", "-option", "ctrl:nocaps,grp:rctrl_switch"
                ]
            )
            lays[current_focus] = 0
            # print(current_focus)
        else:
            if DEBUG:
                f.write(f"{current_focus} found.\n".encode())
            val = lays[current_focus]
            if val == 0:
                subprocess.run(
                    [
                        "setxkbmap", "-layout", "us,am", "-variant",
                        ",phonetic-alt", "-option",
                        "ctrl:nocaps,grp:rctrl_switch"
                    ]
                )
                if DEBUG:
                    f.write(f"{current_focus} setting to us.\n".encode())
            else:
                subprocess.run(
                    [
                        "setxkbmap", "-layout", "am,us", "-variant",
                        "phonetic-alt,", "-option",
                        "ctrl:nocaps,grp:rctrl_switch"
                    ]
                )
                if DEBUG:
                    f.write(f"{current_focus} setting to am\n".encode())
        subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])
        previous_focus = current_focus


def on_window_close(i3, e):
    with mutex:
        global deleted_focus
        current_focus = e.container.id
        if current_focus in lays:
            del lays[current_focus]
            deleted_focus = current_focus


def on_workspace_focus(i3, e):
    subprocess.run(["dunstify", "-t", "2000", str(e.old.name)])


if DEBUG:
    buffsize = 0
    f = open("/tmp/i3_ipc.log", "wb", buffering=buffsize)

i3.on("window::focus", on_window_focus)
i3.on("window::close", on_window_close)
i3.on("workspace::focus", on_workspace_focus)

signal.signal(signal.SIGUSR1, handle_pdb)
i3.main()
