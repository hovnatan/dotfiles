#!/usr/bin/python3

import subprocess
import time
import re
import pathlib
import sys

DROPBOX_CMDLINE = pathlib.Path.home() / ".dotfiles/bin/dropbox.py"

status = subprocess.check_output([DROPBOX_CMDLINE,
                                  'start']).decode(sys.stdout.encoding)
if not status or re.search("already running", status):
    sys.exit(5)
while True:
    status = subprocess.check_output([DROPBOX_CMDLINE,
                                      'status']).decode(sys.stdout.encoding)
    if re.search("Up to date", status):
        subprocess.call([DROPBOX_CMDLINE, 'stop'])
        break
    time.sleep(1)
