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
NUM_WORKSPACES_TO_FOLLOW = 10

if False:
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


f = open("/tmp/ipc_server.log", "w")
sys.stdout = f


class SizedAndUpdatedOrderedDict(collections.OrderedDict):
    'Limit size, evicting the least recently looked-up key when full'

    def __init__(self, maxsize=4, *args, **kwds):
        self.maxsize = maxsize
        super().__init__(*args, **kwds)

    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        self.move_to_end(key)
        if self.maxsize != 0 and len(self) > self.maxsize:
            oldest = next(iter(self))
            del self[oldest]


class FocusWatcher:
    def __init__(self, debug=False):
        self.debug = debug
        self.i3 = i3ipc.Connection()
        if self.debug:
            print("Connection to I3 established.")
        self.i3.on('window::focus', self.on_window_focus)
        self.i3.on("window::close", self.on_window_close)
        self.i3.on("workspace::focus", self.on_workspace_focus)
        self.i3.on('ipc_shutdown', self.on_shutdown)
        self.listening_socket = socket.socket(
            socket.AF_UNIX, socket.SOCK_STREAM
        )
        if os.path.exists(SOCKET_FILE):
            os.remove(SOCKET_FILE)
        self.listening_socket.bind(SOCKET_FILE)
        self.listening_socket.listen(1)
        if self.debug:
            print("Connection to socket established.")

        self.window_list = SizedAndUpdatedOrderedDict(maxsize=0)
        self.window_list_lock = threading.RLock()
        self.mode_w = False
        self.mode_w_lock = threading.RLock()
        self.w_index = 0
        self.window_current_lock = threading.RLock()
        self.current_w = -1
        self.ws_window_list = set()
        self.ws_w_curr_length = -1

        self.workspace_list_lock = threading.RLock()
        self.workspace_list = SizedAndUpdatedOrderedDict(
            maxsize=NUM_WORKSPACES_TO_FOLLOW
        )
        self.mode_ws = False
        self.mode_ws_lock = threading.RLock()
        self.ws_index = 0
        self.workspace_current_lock = threading.RLock()
        self.current_ws = -1

    @staticmethod
    def on_shutdown(i3conn):
        try:
            sh.pkill("-f", "i3_custom_ipc_client.py")
        except sh.ErrorReturnCode:
            pass
        sys.exit(0)

    def on_window_close(self, i3conn, event):
        if self.debug:
            print("Connection to socket established.")
        with self.window_list_lock:
            window_id = event.container.id
            if window_id in self.window_list:
                del self.window_list[window_id]

    def on_press_or_release_tab(self, key):
        if key != keyboard.Key.tab:
            with self.mode_ws_lock:
                self.mode_ws = False
            with self.workspace_current_lock:
                if self.current_ws != -1:
                    with self.workspace_list_lock:
                        self.workspace_list[self.current_ws] = True
            return False
        return True

    def on_press_or_release_grave(self, key):
        try:
            char = key.char
        except AttributeError:
            char = 'a'
        if char != '`' and char != '՝':
            if self.debug:
                print("Grave closing ", char)

            with self.mode_w_lock:
                self.mode_w = False
            with self.window_current_lock:
                if self.current_w != -1:
                    with self.window_list_lock:
                        c_w = self.window_list[self.current_w]
                        if self.debug:
                            print("WL c", c_w)
            self.keyboard_layout_setup(self.current_w)
            return False
        return True

    def latest_window_on_ws(self):
        with self.mode_w_lock:
            if not self.mode_w:
                self.ws_window_list = set()
                for x in self.i3.get_tree().find_focused().workspace(
                ).descendents():
                    if not x.window:
                        continue
                    self.ws_window_list.add(x.id)
                self.ws_w_curr_length = len(self.ws_window_list)
                if self.debug:
                    print(
                        "Current ws windows", self.ws_window_list,
                        self.window_list
                    )
                if self.ws_w_curr_length < 2:
                    return
                self.mode_w = True
                self.w_index = 1
                keyboard.Listener(
                    on_release=self.on_press_or_release_grave,
                    on_press=self.on_press_or_release_grave
                ).start()
        with self.window_list_lock:
            k = self.w_index % self.ws_w_curr_length
            check_k = 0
            for window in reversed(self.window_list):
                if window in self.ws_window_list:
                    if check_k != k:
                        check_k += 1
                        continue
                    self.i3.command('[con_id="%d"] focus' % window)
                    break
            self.w_index += 1

    def workspace_back(self):
        with self.mode_ws_lock:
            if not self.mode_ws:
                self.mode_ws = True
                self.ws_index = 1
                keyboard.Listener(
                    on_release=self.on_press_or_release_tab,
                    on_press=self.on_press_or_release_tab
                ).start()
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
            if self.debug:
                print(f"hello ws {self.current_ws}")
            if not self.current_ws.isdigit():
                return
            with self.mode_ws_lock:
                if self.mode_ws:
                    return
            with self.workspace_list_lock:
                self.workspace_list[self.current_ws] = True

    def keyboard_layout_setup(self, window_id):
        if self.debug:
            print("Keyboard setup with", window_id)
        with self.window_list_lock:
            if self.window_list:
                previous_focus = next(reversed(self.window_list))
                result = subprocess.run(
                    ['check_layout.sh'], stdout=subprocess.PIPE
                )
                if result.stdout.decode() == "am":
                    self.window_list[previous_focus] = 1
                else:
                    self.window_list[previous_focus] = 0
            key = 0
            if window_id in self.window_list:
                key = self.window_list[window_id]
                if key == 0:
                    subprocess.run(["setkmap.sh", "us"])
                else:
                    subprocess.run(["setkmap.sh", "am"])
                del self.window_list[window_id]
            else:
                subprocess.run(["setkmap.sh", "us"])
            self.window_list[window_id] = key
            subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])

    def on_window_focus(self, i3conn, event):
        window_id = event.container.props.id
        if self.debug:
            print(f"window focus on {window_id}")
        with self.window_current_lock:
            self.current_w = window_id
        with self.mode_w_lock:
            if self.mode_w:
                return
        self.keyboard_layout_setup(window_id)

    def launch_i3(self):
        if self.debug:
            print("i3 started")
        self.i3.main()

    def launch_server(self):
        selector = selectors.DefaultSelector()

        def accept(sock):
            conn, addr = sock.accept()
            selector.register(conn, selectors.EVENT_READ, read)

        def read(conn):
            data = conn.recv(1024)
            if self.debug:
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
            elif data == b'next_w_on_ws':
                self.latest_window_on_ws()
                conn.send("OK".encode())
            elif data == b'debug':
                with self.window_list_lock:
                    all_winds = str(self.window_list)
                with self.workspace_list_lock:
                    all_ws = str(self.workspace_list)
                conn.send((all_winds + " " + all_ws).encode())
            elif data == b'set_debug':
                self.debug = True
                conn.send("debug flag set".encode())
            elif not data:
                if self.debug:
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
        threads.append(threading.Thread(target=self.launch_server, daemon=True))
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

    focus_watcher = FocusWatcher()
    focus_watcher.run()
