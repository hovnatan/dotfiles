#!/usr/bin/env python3

import os
import sys
import socket
import selectors
import subprocess
import threading
import collections

import sh

import i3ipc
from pynput import keyboard

SOCKET_FILE = '/tmp/i3_focus_last'
NUM_WORKSPACES_TO_FOLLOW = 3

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

    # f = open("/tmp/ipc_server.log", "w")
    # sys.stdout = f

    def listen():
        signal.signal(signal.SIGUSR1, debug)  # Register handler


class SizedAndUpdatedOrderedDict(collections.OrderedDict):
    'Limit size, evicting the least recently looked-up key when full'

    def __init__(self, maxsize=4, *args, **kwds):
        self.maxsize = maxsize
        super().__init__(*args, **kwds)

    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        self.move_to_end(key)
        if len(self) > self.maxsize:
            oldest = next(iter(self))
            del self[oldest]


class FocusWatcher:
    def __init__(self):
        self.i3 = i3ipc.Connection()
        self.i3.on('window::focus', self.on_window_focus)
        self.i3.on("window::close", self.on_window_close)
        self.i3.on("workspace::focus", self.on_workspace_focus)
        self.i3.on("mode", self.on_mode_change)
        self.i3.on('ipc_shutdown', self.on_shutdown)
        self.listening_socket = socket.socket(
            socket.AF_UNIX, socket.SOCK_STREAM
        )
        if os.path.exists(SOCKET_FILE):
            os.remove(SOCKET_FILE)
        self.listening_socket.bind(SOCKET_FILE)
        self.listening_socket.listen(1)
        self.window_list = collections.OrderedDict()
        self.window_list_lock = threading.Lock()
        self.workspace_list_lock = threading.RLock()
        self.workspace_list = SizedAndUpdatedOrderedDict(
            maxsize=NUM_WORKSPACES_TO_FOLLOW
        )
        self.mode_ws = False
        self.ws_index = 0
        self.workspace_current_lock = threading.RLock()
        self.current_ws = -1

    def on_shutdown(self, i3conn):
        try:
            sh.pkill("-f", "i3_custom_ipc_client.py")
        except sh.ErrorReturnCode:
            pass
        sys.exit(0)

    def on_window_close(self, i3conn, event):
        with self.window_list_lock:
            window_id = event.container.id
            if window_id in self.window_list:
                del self.window_list[window_id]

    def on_mode_change(self, i3conn, event):
        with self.workspace_list_lock:
            if event.change != "ws_change":
                if self.mode_ws:
                    self.mode_ws = False
                    with self.workspace_current_lock:
                        if self.current_ws != -1:
                            self.workspace_list[self.current_ws] = True
                return
            keyboard.Listener(
                on_release=self.on_release, on_press=self.on_release
            ).start()
            self.mode_ws = True
            self.ws_index = 1
            self.workspace_back()

    def on_release(self, key):
        if key == keyboard.Key.alt:
            self.i3.command("mode default")
            return False

    def workspace_back(self):
        with self.workspace_list_lock:
            curr_length = len(self.workspace_list)
            if curr_length < 2:
                return
            k = self.ws_index % curr_length
            for check_k, ws in enumerate(reversed(self.workspace_list)):
                if check_k != k:
                    continue
                self.i3.command(f"workspace {ws}")
                break
            self.ws_index += 1

    def on_workspace_focus(self, i3conn, event):
        with self.workspace_current_lock:
            self.current_ws = str(event.current.name)
            if DEBUG:
                print(f"hello ws {self.current_ws}")
            with self.workspace_list_lock:
                if self.mode_ws:
                    return
                if not self.current_ws.isdigit():
                    return
                self.workspace_list[self.current_ws] = True

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
                print(f"Received {data.decode()}")
            if data == b'switch':
                # with self.window_list_lock:
                #     if DEBUG:
                #         print("reading")
                #     tree = self.i3.get_tree()
                #     windows = set(w.id for w in tree.leaves())
                #     for k, window_id in enumerate(reversed(self.window_list)):
                #         if k == 0:
                #             continue
                #         if window_id not in windows:
                #             del self.window_list[window_id]
                #         else:
                #             self.i3.command('[con_id=%s] focus' % window_id)
                #             break
                pass
            # elif data == b'last_ws':
            #     last_ws = '.'.join(
            #         [str(k) for k in reversed(self.workspace_list)]
            #     )
            #     if last_ws:
            #         conn.send(last_ws.encode())
            #     else:
            #         conn.send("nws".encode())
            elif data == b'next_ws':
                self.workspace_back()
                conn.send("OK".encode())
            elif not data:
                if DEBUG:
                    print(f"Closing connection.")
                selector.unregister(conn)
                conn.close()
            else:
                conn.send("Unrecognized command.".encode())

        selector.register(self.listening_socket, selectors.EVENT_READ, accept)

        while True:
            for key, event in selector.select():
                callback = key.data
                callback(key.fileobj)

    def run(self):
        threads = []
        threads.append(threading.Thread(target=self.launch_i3))
        threads.append(threading.Thread(target=self.launch_server))
        threads[-1].daemon = True
        for t in threads:
            t.start()


if __name__ == '__main__':
    res = sh.grep(
        sh.ps("aux", cols=1000), "--color=never", "i3_custom_ipc_server.py"
    )
    for line in res.splitlines():
        if "python3" in line and str(os.getpid()) not in line:
            print("I3 IPC server already running")
            sys.exit(1)

    try:
        sh.pkill("-f", "i3_custom_ipc_client.py")
    except sh.ErrorReturnCode:
        pass
    if DEBUG:
        listen()

    focus_watcher = FocusWatcher()
    focus_watcher.run()
