#!/bin/bash

# Example locker script -- demonstrates how to use the --transfer-sleep-lock
# option with i3lock's forking mode to delay sleep until the screen is locked.

## CONFIGURATION ##############################################################
LOCK_FILE="$HOME/tmp/$USER-lock.file"
if [[ -f "$LOCK_FILE" ]] ; then
  echo "Trying to lock already locked system." | systemd-cat
  if [[ -e /dev/fd/${XSS_SLEEP_LOCK_FD:--1} ]]; then
    exec {XSS_SLEEP_LOCK_FD}<&-
  fi
  exit
fi

# find all sshfs
# ps -eo args | grep dhcpcd | head -n -1

echo $$ > "$LOCK_FILE"

TMPBG="/tmp/screen-$USER.png"

B='#00000000'  # blank
C='#ffffff22'  # clear ish
D='#689d68cc'  # default
T='#d79921ff'  # text
W='#cc241dbb'  # wrong
V='#b16286bb'  # verifying

i3lock_options="-i $TMPBG --insidevercolor=$C --ringvercolor=$V --insidewrongcolor=$C --ringwrongcolor=$W --insidecolor=$B --ringcolor=$D --linecolor=$B --separatorcolor=$D --verifcolor=$T --wrongcolor=$T --timecolor=$T --datecolor=$T --layoutcolor=$T --keyhlcolor=$W --bshlcolor=$W --screen 1 --clock --indicator --timestr=%H:%M:%S --keylayout 2 --datestr=\"%A %m/%d/%Y\""

DEVICE_TO_DISABLE=$(xinput --list | sed -rn 's/.*Mouse.*Mouse.*id=([0-9]+).*/\1/p')
xinput --disable $DEVICE_TO_DISABLE
scrot -o $TMPBG && convert $TMPBG -scale 5% -scale 2000% $TMPBG
if [[ "$XSS_SLEEP_LOCK_FD" != "" ]]; then
  ~/.dotfiles/check-i3lock.sh {XSS_SLEEP_LOCK_FD}<&- &
else
  ~/.dotfiles/check-i3lock.sh &
fi
zathura_save.sh last add_hname

if pkill -xu $EUID -0 workrave; then
  dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetUsageMode string:normal
fi

DUNST_LOCK_FILE="$HOME/tmp/$USER-dunst-lock.file"
if [[ ! -f "$DUNST_LOCK_FILE" ]] ; then
  dunstify DUNST_COMMAND_PAUSE
  echo $$ > "$DUNST_LOCK_FILE"
  DUNST_PAUSED="1"
fi

kill_i3lock() {
    pkill -xu $EUID "$@" i3lock
}

on_exit() {
    kill_i3lock
    kill $(jobs -p)
    xinput --enable $DEVICE_TO_DISABLE
    xset -dpms
    if pkill -xu $EUID -0 workrave; then
      dbus-send --print-reply --dest=org.workrave.Workrave /org/workrave/Workrave/Core org.workrave.CoreInterface.SetUsageMode string:reading
    fi
    rm "$LOCK_FILE"
    if [[ "$DUNST_PAUSED" != "" ]] ; then
      dunstify DUNST_COMMAND_RESUME
      rm "$DUNST_LOCK_FILE"
    fi
}

trap on_exit TERM INT EXIT

# We set a trap to kill the locker if we get killed, then start the locker and
# wait for it to exit. The waiting is not that straightforward when the locker
# forks, so we use this polling only if we have a sleep lock to deal with.
if [[ -e /dev/fd/${XSS_SLEEP_LOCK_FD:--1} ]]; then
    echo "Going to sleep." | systemd-cat
    killall -9 sshfs
    # we have to make sure the locker does not inherit a copy of the lock fd
    eval "i3lock $i3lock_options" {XSS_SLEEP_LOCK_FD}<&-

    # now close our fd (only remaining copy) to indicate we're ready to sleep
    exec {XSS_SLEEP_LOCK_FD}<&-

    # check if i3lock still running by running pkill -0 i3lock
    while kill_i3lock -0; do
        sleep 0.5
    done
else
    AUTO_LOCK_FILE="$HOME/tmp/$USER-auto-lock.file"
    if [[ ! -f "$AUTO_LOCK_FILE" ]] ; then
      eval "i3lock -n $i3lock_options"
    fi
fi
