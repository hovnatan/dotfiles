import ranger.api
import subprocess
from ranger.api.commands import *


def hook_init(fm):
    def update_autojump(signal):
        subprocess.Popen(["fish", "-c", "__z_add"])

    fm.signal_bind('cd', update_autojump)


ranger.api.hook_init = hook_init
