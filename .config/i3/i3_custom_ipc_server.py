#!/usr/bin/env python3

import os
import time
import sys
import queue
import subprocess
import threading
import logging

import sh

from systemd.journal import JournalHandler

import i3ipc

TIME_TO_SYNC = 0.1
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


class FocusWatcher:
    def __init__(self, debug=False):
        self.debug = debug
        self.set_debug(debug)
        self.i3 = i3ipc.Connection()
        # logger.debug("Connection to I3 established.")
        self.i3.on('window::focus', self.on_window_focus)
        self.i3.on("window::close", self.on_window_close)
        self.i3.on('ipc_shutdown', self.on_shutdown)

        self.w_queue = queue.SimpleQueue()
        self.window_list_lock = threading.RLock()
        self.window_list = {}
        self.current_w = -1
        self.current_key = DEFAULT_KEYBOARD_LAYOUT
        self.current_key_lock = threading.RLock()

    @staticmethod
    def on_shutdown(i3conn):
        sys.exit(0)

    def on_window_close(self, i3conn, event):
        window_id = event.container.id
        # logger.debug("Closing %s.", window_id)
        if self.current_w == window_id:
            self.current_w = None
        with self.window_list_lock:
            if window_id in self.window_list:
                del self.window_list[window_id]

    def on_window_focus(self, i3conn, event):
        window_id = event.container.id
        self.current_w = window_id
        self.w_queue.put((window_id, time.time()))

    def launch_i3(self):
        # logger.debug("i3 started.")
        self.i3.main()

    @staticmethod
    def set_debug(debug=False):
        if debug:
            logger.setLevel(logging.DEBUG)

    def w_thread(self):
        while True:
            w, t = self.w_queue.get()
            if not self.w_queue.empty():
                continue
            ct = time.time()
            time.sleep(max(0.0, TIME_TO_SYNC - (ct - t)))
            if w == self.current_w:
                with self.window_list_lock:
                    key = self.window_list.get(
                        self.current_w, DEFAULT_KEYBOARD_LAYOUT
                    )
                with self.current_key_lock:
                    if key != self.current_key:
                        subprocess.run(["xkb-switch", "-s", key])

    def kb_watch_thread(self):
        result = subprocess.Popen(['xkb-switch', '-W'], stdout=subprocess.PIPE)
        while True:
            line = result.stdout.readline().decode().rstrip()
            # logger.debug("Keyboard switch to %s received.", line)
            with self.current_key_lock:
                self.current_key = line
            if self.current_w:
                with self.window_list_lock:
                    self.window_list[self.current_w] = line
            subprocess.run(["pkill", "-RTMIN+10", "i3blocks"])

    def run(self):
        threads = []
        threads.append(threading.Thread(target=self.launch_i3))
        threads.append(
            threading.Thread(target=self.kb_watch_thread, daemon=True)
        )
        threads.append(threading.Thread(target=self.w_thread, daemon=True))
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
