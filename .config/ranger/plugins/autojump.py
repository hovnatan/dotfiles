import ranger.api
import subprocess
from ranger.api.commands import *
import threading
import time
import queue

cwd_queue = queue.SimpleQueue()

TIME_TO_SYNC = 20
cwd = None


def cd_watch_thread():
    while True:
        d, t = cwd_queue.get()
        if not cwd_queue.empty():
            continue
        ct = time.time()
        time.sleep(max(0.0, TIME_TO_SYNC - (ct - t)))
        if d == cwd:
            subprocess.run(["fish", "-c", "__z_add"])


threading.Thread(target=cd_watch_thread, daemon=True).start()


def hook_init(fm):
    def update_autojump(signal):
        global cwd
        cwd = signal["new"]
        cwd_queue.put((cwd, time.time()))

    fm.signal_bind('cd', update_autojump)


ranger.api.hook_init = hook_init
