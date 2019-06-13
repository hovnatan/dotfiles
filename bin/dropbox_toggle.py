#!/usr/bin/python3

import subprocess
import re
import pathlib
import sys

DROPBOX_CMDLINE = pathlib.Path.home() / "Dropbox/scripts/dropbox.py"

status = subprocess.check_output([DROPBOX_CMDLINE,
                                  'status']).decode(sys.stdout.encoding)
if not status or re.search("isn't running", status):
    subprocess.call([DROPBOX_CMDLINE, 'start'])
else:
    subprocess.call([DROPBOX_CMDLINE, 'stop'])
