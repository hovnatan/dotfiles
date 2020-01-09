import i3ipc
import sh

i3 = i3ipc.Connection()

for con in i3.get_tree():
    if con.window and con.parent.type != 'dockarea':
        if con.window_class != "Zathura":
            continue
        pid = sh.cut(
            sh.grep(sh.xprop("-id", con.window), "-m", "1", "PID"), "-d", " ",
            "-f", "3"
        )
        pid = pid.strip()
        workspace = con.workspace().name
        print(f"{pid}:{workspace}")
