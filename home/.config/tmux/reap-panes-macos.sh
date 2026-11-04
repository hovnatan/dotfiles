#!/usr/bin/env bash
# The Mac half of reap-panes.sh, which hands over here: end what a closed pane
# left running in the background, as well as a Mac allows.
#
#   reap-panes-macos.sh <socket path>
#
# A Mac has no scopes, so nothing records which pane a detached job came from.
# What it keeps is the environment tmux gave the pane, inherited by the job:
#
#   ps -E: pid 812, ppid 1, TMUX=<socket>,4021,3 TMUX_PANE=%7
#     parent is launchd       -> detached: nothing else will end it
#     4021 is not this server, and no tmux runs there    -> server gone: stop
#     4021 is another tmux, its socket file lost or taken -> its own:    keep
#     4021 is this server, %7 is not a live pane         -> pane gone:   stop
#     %7 is a live pane                                  -> its pane's:  keep
#
# Best effort, and the gaps are a Mac's:
#   - ps hides the environment of Apple-signed binaries (/bin/sleep,
#     /usr/bin/ssh): such a job is not seen and runs on. Nix-built ones are.
#   - a job that clears its environment is not seen either.
#   - a helper shared with other panes (gpg-agent, an ssh control master) goes
#     with the pane that first started it. Each stop is logged for that reason.
# Only a detached process is touched: one with a parent is a live pane's, or
# ends with a parent that is stopped here. The tmux server is never one, though
# one started from a pane carries that pane's variables.
#
# Each stop goes to the tmux hooks' log, the job's arguments but not its
# environment, which may hold secrets:
#   2026-11-04T19:36:30Z reaped pid 812 (pane %7 of server 4021): node proxy.js
set -u

sock=${1:?usage: reap-panes-macos.sh <socket path>}

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"

# Processes first, tmux after: a pane born in between is then in the list of
# panes, where the other order would read its first job as a closed pane's.
if ! listing=$(ps -Eww -U "$(id -u)" -o pid=,ppid=,command=); then
  event_log_note tmux_hooks "FAILED to list processes for $sock"
  echo "reap-panes-macos.sh: ps could not list this user's processes" >&2
  exit 1
fi

# No answer is a server gone with its last session, or one that cannot be
# reached: nothing here can tell what is live, so stop nothing. The next
# server's start comes back here (~/.tmux.conf).
server=$(tmux -S "$sock" display-message -p '#{pid}' 2>/dev/null) || exit 0

# A server that answers but gives no list stops nothing, and says so. Until its
# first session exists tmux refuses `list-panes -a` ("no current target"), and
# the start sweep runs from the config, before that session: so wait for it.
listed=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  panes=$(tmux -S "$sock" list-panes -a -F '#{pane_id}' 2>/dev/null) && listed=1 && break
  tmux -S "$sock" display-message -p '' >/dev/null 2>&1 || exit 0
  sleep 0.2
done
if [ -z "$listed" ]; then
  event_log_note tmux_hooks "FAILED to list the panes of server $server at $sock"
  echo "reap-panes-macos.sh: server $server at $sock answers but lists no panes; nothing stopped" >&2
  exit 1
fi
panes=" $(tr '\n' ' ' <<<"$panes")"

pane_re=' TMUX_PANE=(%[0-9]+)'
stopped=""
while read -r pid ppid rest; do
  [ "$ppid" = 1 ] || continue
  case " $rest" in *" TMUX=$sock,"*) ;; *) continue ;; esac
  [[ " $rest" =~ $pane_re ]] || continue
  pane=${BASH_REMATCH[1]}
  owner=${rest##* TMUX="$sock",}
  owner=${owner%%,*}
  if [ "$owner" = "$server" ]; then
    case $panes in *" $pane "*) continue ;; esac
  else
    alive=$(ps -o command= -p "$owner") && case ${alive%% *} in tmux | tmux: | */tmux) continue ;; esac
  fi

  args=$(ps -o command= -p "$pid") || continue
  case ${args%% *} in tmux | tmux: | */tmux) continue ;; esac

  kill "$pid" 2>/dev/null || continue
  event_log_note tmux_hooks "reaped pid $pid (pane $pane of server $owner): $(cut -c1-300 <<<"$args")"
  stopped+=" $pid"
done <<<"$listing"

# What ignored the TERM. launchd reaps it, so the pid does not linger.
[ -n "$stopped" ] || exit 0
sleep 1
for pid in $stopped; do
  kill -0 "$pid" 2>/dev/null || continue
  kill -KILL "$pid" 2>/dev/null && event_log_note tmux_hooks "reaped pid $pid with KILL: it ignored TERM"
done
