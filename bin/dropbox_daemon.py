#!/usr/bin/python3

import subprocess
import time
import re
import pathlib
import sys
import signal

status = subprocess.check_output(['pgrep', '-f', 'dropbox_daemon.py']).decode(
    sys.stdout.encoding
)
nlines = status.count('\n')
if nlines > 1:
    sys.exit(4)


class GracefulKiller:
    kill_now = False

    def __init__(self):
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, signum, frame):
        self.kill_now = True


DROPBOX_CMDLINE = pathlib.Path.home() / "Dropbox/scripts/dropbox.py"
CONSEQ_IDLE = 20

killer = GracefulKiller()

while not killer.kill_now:
    subprocess.call([DROPBOX_CMDLINE, 'start'])
    conseq_idle = CONSEQ_IDLE
    while not killer.kill_now:
        status = subprocess.check_output([DROPBOX_CMDLINE, 'status']).decode(
            sys.stdout.encoding
        )
        if re.search("Up to date", status):
            conseq_idle -= 1
        else:
            conseq_idle = CONSEQ_IDLE
        if conseq_idle <= 0:
            subprocess.call([DROPBOX_CMDLINE, 'stop'])
            break
        time.sleep(1)
    if not killer.kill_now:
        time.sleep(900)

status = subprocess.check_output([DROPBOX_CMDLINE,
                                  'status']).decode(sys.stdout.encoding)
if status and not re.search("Dropbox isn't running!", status):
    conseq_idle = CONSEQ_IDLE
    while True:
        status = subprocess.check_output([DROPBOX_CMDLINE, 'status']).decode(
            sys.stdout.encoding
        )
        if not status:
            conseq_idle = 0
        elif re.search("Up to date", status):
            conseq_idle -= 1
        elif re.search("Dropbox isn't running!", status):
            conseq_idle = 0
        else:
            conseq_idle = CONSEQ_IDLE
        if conseq_idle <= 0:
            subprocess.call([DROPBOX_CMDLINE, 'stop'])
            break
        time.sleep(1)
