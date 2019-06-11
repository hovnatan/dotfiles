#!/usr/bin/python3

import subprocess
import time
import re
import pathlib
import sys

DROPBOX_CMDLINE = pathlib.Path.home() / "Dropbox/scripts/dropbox.py"
CONSEQ_IDLE = 20

while True:
    subprocess.call([DROPBOX_CMDLINE, 'start'])
    conseq_idle = CONSEQ_IDLE
    while True:
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
    time.sleep(900)
