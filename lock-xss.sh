#!/bin/bash

# Example locker script -- demonstrates how to use the --transfer-sleep-lock
# option with i3lock's forking mode to delay sleep until the screen is locked.

## CONFIGURATION ##############################################################

if [ $(pgrep -x "i3lock") ] || [$(pgrep -x "lock-xss.sh") ] ; then
  if [[ -e /dev/fd/${XSS_SLEEP_LOCK_FD:--1} ]]; then
    exec {XSS_SLEEP_LOCK_FD}<&-
  fi
  exit 0
fi

TMPBG="/tmp/screen-$USER.png"

B='#00000000'  # blank
C='#ffffff22'  # clear ish
D='#689d68cc'  # default
T='#d79921ff'  # text
W='#cc241dbb'  # wrong
V='#b16286bb'  # verifying

i3lock_options="-i $TMPBG --insidevercolor=$C --ringvercolor=$V --insidewrongcolor=$C --ringwrongcolor=$W --insidecolor=$B --ringcolor=$D --linecolor=$B --separatorcolor=$D --verifcolor=$T --wrongcolor=$T --timecolor=$T --datecolor=$T --layoutcolor=$T --keyhlcolor=$W --bshlcolor=$W --screen 1 --clock --indicator --timestr=%H:%M:%S --keylayout 2"

xinput --disable $(xinput --list | sed -rn 's/.*Mouse.*Mouse.*id=([0-9]+).*/\1/p')
scrot -o $TMPBG && convert $TMPBG -scale 5% -scale 2000% $TMPBG
~/.dotfiles/check-i3lock.sh &
xkb-switch -s us
zathura_save.sh last add_hname
sleep 1

# We set a trap to kill the locker if we get killed, then start the locker and
# wait for it to exit. The waiting is not that straightforward when the locker
# forks, so we use this polling only if we have a sleep lock to deal with.
if [[ -e /dev/fd/${XSS_SLEEP_LOCK_FD:--1} ]]; then
    kill_i3lock() {
        pkill -xu $EUID "$@" i3lock
    }

    trap kill_i3lock TERM INT

    # we have to make sure the locker does not inherit a copy of the lock fd
    i3lock $i3lock_options --datestr="%A %m/%d/%Y" {XSS_SLEEP_LOCK_FD}<&-

    # now close our fd (only remaining copy) to indicate we're ready to sleep
    exec {XSS_SLEEP_LOCK_FD}<&-

    while kill_i3lock -0; do
        sleep 0.5
    done
else
    eval $(xdotool getmouselocation --shell)
    if [ "$X" -gt 30 ] || [ "$1" != "" ] ; then
      trap 'kill %%' TERM INT
      i3lock -n $i3lock_options --datestr="%A %m/%d/%Y" &
      wait $!
    fi
fi

trap 'kill $(jobs -p)' EXIT
xinput --enable $(xinput --list | sed -rn 's/.*Mouse.*Mouse.*id=([0-9]+).*/\1/p')
xset -dpms
