import re
import sys

import sh

import i3ipc

PATTERN = re.compile(r'"([^"]*)"')

workspace_to_use = sys.argv[1]

i3 = i3ipc.Connection()

for con in i3.get_tree():
    if con.window and con.parent.type != 'dockarea':
        if con.window_class != "Zathura":
            continue
        xprop = str(sh.xprop("-id", con.window))
        xprop_lines = xprop.split('\n')
        for line in xprop_lines:
            if "PID" in line:
                items = line.split(' ')
                pid = items[2]
                pid = pid.strip()
        for line in xprop_lines:
            if "WM_NAME" in line:
                m = re.findall(PATTERN, line)
                name = m[0]
        workspace = con.workspace().name
        if workspace_to_use in ("", workspace):
            print(f"{pid}:{workspace}:{name}")
