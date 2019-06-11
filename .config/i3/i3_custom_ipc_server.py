#!/usr/bin/env python3

import os
import socket
import selectors
import subprocess
import threading
import collections

import i3ipc

SOCKET_FILE = '/tmp/i3_focus_last'
MAX_WIN_HISTORY = 15

DEBUG = False

if DEBUG:
    import code
    import traceback
    import signal

    def debug(sig, frame):
        """Interrupt running process, and provide a python prompt for
        interactive debugging."""
        d = {'_frame': frame}  # Allow access to frame object.
        d.update(frame.f_globals)  # Unless shadowed by global
        d.update(frame.f_locals)

        i = code.InteractiveConsole(d)
        message = "Signal received : entering python shell.\nTraceback:\n"
        message += ''.join(traceback.format_stack(frame))
        i.interact(message)

    def listen():
        signal.signal(signal.SIGUSR1, debug)  # Register handler


class FocusWatcher:
    def __init__(self):
        self.i3 = i3ipc.Connection()
        self.i3.on('window::focus', self.on_window_focus)
        self.i3.on("window::close", self.on_window_close)
        self.i3.on("workspace::focus", self.on_workspace_focus)
        self.listening_socket = socket.socket(
            socket.AF_UNIX, socket.SOCK_STREAM
        )
        if os.path.exists(SOCKET_FILE):
            os.remove(SOCKET_FILE)
        self.listening_socket.bind(SOCKET_FILE)
        self.listening_socket.listen(1)
        self.window_list = collections.OrderedDict()
        self.window_list_lock = threading.Lock()

    def on_window_close(self, i3conn, event):
        with self.window_list_lock:
            window_id = event.container.id
            if window_id in self.window_list:
                del self.window_list[window_id]

    def on_workspace_focus(self, i3conn, event):
        if DEBUG:
            print("hello")

        subprocess.run(
            [
                "dunstify", "-t", "2000",
                str(event.old.name) + " was previous workspace"
            ]
        )

    def on_window_focus(self, i3conn, event):
        with self.window_list_lock:
            if DEBUG:
                print("on_window_focus")
            if self.window_list:
                previous_focus = next(reversed(self.window_list))
                result = subprocess.run(
                    ['check_layout.sh'], stdout=subprocess.PIPE
                )
                if result.stdout.decode() == "am":
                    self.window_list[previous_focus] = 1
                else:
                    self.window_list[previous_focus] = 0
            window_id = event.container.props.id
            key = 0
            subprocess.run(["setxkbmap", "-option", ""])
            if DEBUG:
                print("on_window_focus2")
            if window_id in self.window_list:
                key = self.window_list[window_id]
                if key == 0:
                    subprocess.run(
                        [
                            "setxkbmap", "-layout", "us,am", "-variant",
                            ",phonetic-alt", "-option",
                            "ctrl:nocaps,grp:rctrl_switch"
                        ]
                    )
                else:
                    subprocess.run(
                        [
                            "setxkbmap", "-layout", "am,us", "-variant",
                            "phonetic-alt,", "-option",
                            "ctrl:nocaps,grp:rctrl_switch"
                        ]
                    )
                del self.window_list[window_id]
            else:
                subprocess.run(
                    [
                        "setxkbmap", "-layout", "us,am", "-variant",
                        ",phonetic-alt", "-option",
                        "ctrl:nocaps,grp:rctrl_switch"
                    ]
                )
            self.window_list[window_id] = key
            subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])

    def launch_i3(self):
        self.i3.main()

    def launch_server(self):
        selector = selectors.DefaultSelector()

        def accept(sock):
            conn, addr = sock.accept()
            selector.register(conn, selectors.EVENT_READ, read)

        def read(conn):
            data = conn.recv(1024)
            if DEBUG:
                print("reading0")
            if data == b'switch':
                with self.window_list_lock:
                    if DEBUG:
                        print("reading")
                    tree = self.i3.get_tree()
                    windows = set(w.id for w in tree.leaves())
                    for k, window_id in enumerate(reversed(self.window_list)):
                        if k == 0:
                            continue
                        if window_id not in windows:
                            del self.window_list[window_id]
                        else:
                            self.i3.command('[con_id=%s] focus' % window_id)
                            break
            elif not data:
                selector.unregister(conn)
                conn.close()

        selector.register(self.listening_socket, selectors.EVENT_READ, accept)

        while True:
            for key, event in selector.select():
                callback = key.data
                callback(key.fileobj)

    def run(self):
        threads = []
        threads.append(threading.Thread(target=self.launch_i3))
        # t_server = threading.Thread(target=self.launch_server)
        for t in threads:
            t.start()


if __name__ == '__main__':
    if DEBUG:
        listen()

    focus_watcher = FocusWatcher()
    focus_watcher.run()
