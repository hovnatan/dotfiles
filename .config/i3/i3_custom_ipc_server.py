#!/usr/bin/env python3

import os
import time
import sys
import queue
import socket
import selectors
import subprocess
import threading
import collections
import logging

import sh

from systemd.journal import JournalHandler

import i3ipc
from pynput import keyboard

SOCKET_FILE = '/tmp/i3_focus_last'
NUM_WORKSPACES_TO_FOLLOW = 10
TIME_TO_SYNC = 1.00
DEFAULT_KEYBOARD_LAYOUT = "us"

format_str = '[%(asctime)s-%(levelname)-8s-%(filename)-20s:%(lineno)-5s] %(message)s'
formatter = logging.Formatter(format_str)

logger = logging.getLogger(__name__)
logger_handler = logging.StreamHandler(sys.stderr)
logger_handler.setFormatter(formatter)
logger.addHandler(logger_handler)
journald_handler = JournalHandler()
journald_handler.setFormatter(logging.Formatter('[%(levelname)s] %(message)s'))
logger.addHandler(journald_handler)

logger.setLevel(logging.INFO)


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
        self.set_debug(debug)
        self.i3 = i3ipc.Connection()
        logger.debug("Connection to I3 established.")
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
        logger.debug("Connection to socket established.")

        self.w_queue = queue.SimpleQueue()
        self.ws_queue = queue.SimpleQueue()
        self.window_list = SizedAndUpdatedOrderedDict(maxsize=0)
        self.window_list_lock = threading.RLock()
        self.alt_on = False
        self.mode_w = False
        self.mode_w_lock = threading.RLock()
        self.w_index = 0
        self.window_current_lock = threading.RLock()
        self.current_w = -1
        self.ws_window_list = set()
        self.ws_w_curr_length = -1
        self.current_key = "us"
        self.current_key_lock = threading.RLock()

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
        logger.debug("Connection to socket established.")
        window_id = event.container.id
        with self.window_current_lock:
            if self.current_w == window_id:
                self.current_w = None
        with self.window_list_lock:
            if window_id in self.window_list:
                del self.window_list[window_id]

    def on_press(self, key):
        logger.debug("key %s pressed.", key)
        if key == keyboard.Key.alt:
            self.alt_on = True
        elif key == keyboard.Key.tab and self.alt_on:
            self.workspace_back()
        else:
            try:
                char = key.char
            except AttributeError:
                pass
            else:
                if key.char in ['`', '՝'] and self.alt_on:
                    self.latest_window_on_ws()

    def on_release(self, key):
        if key == keyboard.Key.alt:
            self.alt_on = False
            with self.mode_w_lock:
                if self.mode_w:
                    logger.debug("Grave closing.")
                    self.window_setup(self.current_w)
                    self.mode_w = False
                    self.window_setup(self.current_w)
            with self.mode_ws_lock:
                if self.mode_ws:
                    logger.debug("Tab closing.")
                    with self.workspace_current_lock:
                        if self.current_ws != -1:
                            with self.workspace_list_lock:
                                self.workspace_list[self.current_ws] = True
                    self.mode_ws = False
                    self.window_setup(self.current_w)

    def latest_window_on_ws(self):
        with self.mode_w_lock:
            if not self.mode_w:
                self.ws_window_list = set()
                for x in self.i3.get_tree().find_focused().workspace(
                ).descendants():
                    if not x.window:
                        continue
                    self.ws_window_list.add(x.id)
                self.ws_w_curr_length = len(self.ws_window_list)
                logger.debug(
                    "Current ws windows %s %s", self.ws_window_list,
                    self.window_list
                )
                if self.ws_w_curr_length < 2:
                    return
                self.mode_w = True
                self.w_index = 1
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

    def ws_thread(self):
        while True:
            ws, t = self.ws_queue.get()
            ct = time.time()
            time.sleep(max(0.0, TIME_TO_SYNC - (ct - t)))
            with self.mode_ws_lock:
                if self.mode_ws:
                    continue
            with self.workspace_current_lock:
                if self.current_ws != ws:
                    continue
            with self.workspace_list_lock:
                self.workspace_list[ws] = True

    def w_thread(self):
        while True:
            w, t = self.w_queue.get()
            ct = time.time()
            time.sleep(max(0.0, TIME_TO_SYNC - (ct - t)))
            with self.mode_w_lock:
                if self.mode_w:
                    continue
            with self.window_current_lock:
                if w == self.current_w:
                    self.window_setup(w)

    def on_workspace_focus(self, i3conn, event):
        cws = str(event.current.name)
        logger.debug("hello ws %s", cws)
        if not cws.isdigit():
            return
        with self.workspace_current_lock:
            self.current_ws = cws
        self.ws_queue.put((cws, time.time()))

    def window_setup(self, window_id):
        logger.debug("Keyboard setup with %s", window_id)
        with self.window_list_lock:
            if window_id in self.window_list:
                key = self.window_list[window_id]
            else:
                key = DEFAULT_KEYBOARD_LAYOUT
                logger.debug("Setting last %s to us", window_id)
            self.window_list[window_id] = key
        with self.current_key_lock:
            if key != self.current_key:
                subprocess.run(["xkb-switch", "-s", key])

    def on_window_focus(self, i3conn, event):
        window_id = event.container.id
        logger.debug("window focus on %s", window_id)
        with self.window_current_lock:
            self.current_w = window_id
        with self.mode_w_lock:
            if self.mode_w:
                return
        with self.mode_ws_lock:
            if self.mode_ws:
                return
        self.w_queue.put((window_id, time.time()))

    def launch_i3(self):
        logger.debug("i3 started")
        self.i3.main()

    @staticmethod
    def set_debug(debug=False):
        if debug:
            logger.setLevel(logging.DEBUG)

    def launch_server(self):
        logger.info("Started i3 IPC server from hovnatan.")
        selector = selectors.DefaultSelector()

        def accept(sock):
            conn, addr = sock.accept()
            selector.register(conn, selectors.EVENT_READ, read)

        def read(conn):
            data = conn.recv(1024)
            logger.debug("Received %s", data.decode())
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
            elif data == b'debug':
                with self.window_list_lock:
                    all_winds = str(self.window_list)
                with self.workspace_list_lock:
                    all_ws = str(self.workspace_list)
                conn.send((all_winds + " " + all_ws).encode())
            elif data == b'set_debug':
                self.set_debug(True)
                conn.send("debug flag set".encode())
            elif not data:
                logger.debug("Closing connection.")
                selector.unregister(conn)
                conn.close()
            else:
                conn.send("Unrecognized command.".encode())

        selector.register(self.listening_socket, selectors.EVENT_READ, accept)

        while True:
            for key, event in selector.select():
                callback = key.data
                callback(key.fileobj)

    def kb_watch_thread(self):
        result = subprocess.Popen(['xkb-switch', '-W'], stdout=subprocess.PIPE)
        while True:
            line = result.stdout.readline().decode().rstrip()
            logger.debug("Keyboard switch to %s received.", line)
            with self.current_key_lock:
                self.current_key = line
            with self.window_list_lock:
                for window in reversed(self.window_list):
                    self.window_list[window] = line
                    logger.debug("Keyboard for %s switch to %s.", window, line)
                    break
            subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])

    def run(self):
        keyboard.Listener(on_press=self.on_press,
                          on_release=self.on_release).start()
        threads = []
        threads.append(threading.Thread(target=self.launch_i3))
        threads.append(threading.Thread(target=self.launch_server, daemon=True))
        threads.append(threading.Thread(target=self.ws_thread, daemon=True))
        threads.append(threading.Thread(target=self.w_thread, daemon=True))
        threads.append(
            threading.Thread(target=self.kb_watch_thread, daemon=True)
        )
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

    focus_watcher = FocusWatcher(len(sys.argv) > 1)
    focus_watcher.run()
