#!/usr/bin/env bash
# tmux hook for every pane that closes and every server that starts (declared
# in ~/.tmux.conf): on the socket it is given, stop the systemd scope of every
# pane that no longer exists, ending whatever a pane left running in the
# background there. On a Mac, which has no scopes, reap-panes-macos.sh does
# what it can instead.
#
#   reap-panes.sh <socket path>
#
# A scope is kept while it holds a live pane's own process, and a pane's own
# process is the one thing in a scope whose parent is a tmux server. A process
# started from the pane, detached or not, stays in the scope it was born in.
# So does a tmux server started from a pane; with sessions of its own to lose,
# its scope is kept too.
#
#   tmux-spawn-a.scope  fish (child of a tmux server), a proxy it detached  -> kept
#   tmux-spawn-b.scope  a proxy, its pane closed (parent: systemd)          -> stopped
#
# Only this socket's scopes are looked at, however its server started. tmux
# names the server in each scope's description, "tmux child pane 812 launched
# by process 4021" (see ours, below, for a server that has since gone). A server
# that cannot be reached is a live server of some other socket here, and loses
# nothing.
#
# tmux 3.7 runs each pane in a scope of its own. A process a session detached
# -- setsid, nohup, a tool's background job -- stays in its pane's scope when
# the pane closes, so the scope stays active, seen 2026-10-22 held by a
# cloud-sql-proxy:
#
#   tmux-spawn-<uuid>.scope         active: its pane is gone, but
#     `- cloud-sql-proxy ...        a session's background job is not
#
# So what a pane starts ends with it, when the pane closes, not when some
# later session does:
#
#   pane-exited       its program exited    \
#   after-kill-pane   kill-pane              |  (~/.tmux.conf)
#   window-unlinked   kill-window, and each  |-> reap-panes.sh <socket>
#                     window of a session    |   every pane scope that holds
#                     killed                 |   no live pane's own process
#   session-closed    the backstop          /
#
#   server start      a server's last session  -> reap-panes.sh <socket>
#                     takes the hook with it,
#                     so the next one sweeps
# Not the closed pane's own scope alone: by hook time its pid is gone, so
# /proc can no longer say which scope it ran in. Looking at every scope finds
# that one, plus anything an earlier reap missed.
# One close fires several of these (kill-session: one window-unlinked per
# window, then session-closed), which then run side by side; see the loop
# below for why that is safe.
#
# A job meant to outlive its pane belongs in a unit of its own:
#   systemd-run --user --unit=<name> <command>
#
# Each scope stopped is logged with what ran in it (the tmux hooks' log):
#   2026-10-22T19:36:30Z reaped tmux-spawn-7c10....scope: 2130207 cloud-sql-proxy --auto-iam-authn ...
set -u

sock=${1:?usage: reap-panes.sh <socket path>}

[ "$(uname)" != Darwin ] || exec "${0%/*}/reap-panes-macos.sh" "$sock"

# No user manager, as in a container: no scopes, so nothing to stop. A server
# started from an ssh login may lack the variable systemctl --user needs, while
# tmux gives its panes scopes all the same.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[ -S "$XDG_RUNTIME_DIR/systemd/private" ] || exit 0

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"

# unit_up <unit>: true while the unit is loaded and not inactive or failed.
unit_up() {
  [ "$(systemctl --user show -p LoadState --value "$1")" = loaded ] || return 1
  case $(systemctl --user show -p ActiveState --value "$1") in inactive | failed) return 1 ;; esac
}
# procs_of <unit>: the file listing the unit's processes, failing when the
# unit has none to list (gone, or not up).
procs_of() {
  local cg
  cg=$(systemctl --user show -p ControlGroup --value "$1")
  [ -n "$cg" ] && [ -r "/sys/fs/cgroup$cg/cgroup.procs" ] && echo "/sys/fs/cgroup$cg/cgroup.procs"
}
# no_procs <unit>: an unreadable process list of a unit that is up is an
# error, not a skip -- on a cgroup v1 or hybrid host that is every scope,
# and the leftovers this exists to stop would pile up unseen.
no_procs() {
  event_log_note tmux_hooks "FAILED to read $1's processes"
  echo "reap-panes.sh: $1 is up but its processes cannot be read under /sys/fs/cgroup$(systemctl --user show -p ControlGroup --value "$1"); this needs the unified cgroup v2 hierarchy at /sys/fs/cgroup" >&2
  exit 1
}
# ours <unit> <file listing its processes>: true when the scope is this
# socket's. A server gone leaves one record of its socket, the TMUX variable
# its panes passed on; a job that cleared its environment has none, and stays.
#
#   process 4021 is the server at this socket   -> ours
#   process 4021 is another live tmux server    -> not ours
#   no such server: a process has TMUX=<this socket>,...   -> ours
ours() {
  local desc owner pid vars
  desc=$(systemctl --user show -p Description --value "$1")
  owner=${desc##* launched by process }
  case $owner in
    "" | *[!0-9]*)
      unit_up "$1" || return 1
      event_log_note tmux_hooks "FAILED to read the server of $1 from: $desc"
      echo "reap-panes.sh: $1 is described as '$desc', naming no server; has tmux changed that text?" >&2
      exit 1
      ;;
  esac
  [ "$owner" = "$server" ] && return 0
  [ "$(cat "/proc/$owner/comm" 2>/dev/null)" = "tmux: server" ] && return 1
  while read -r pid; do
    vars=$(tr '\0' '\n' 2>/dev/null <"/proc/$pid/environ") || continue
    case $'\n'$vars in *$'\n'"TMUX=$sock,"*) return 0 ;; esac
  done <"$2"
  return 1
}

# holds_pane <file listing a scope's processes>: true when one of them is a
# child of a tmux server, as a pane's own process and nothing else there is,
# or a tmux server itself.
# By status, not stat: "tmux: server" has a space, which shifts stat's fields.
holds_pane() {
  local pid parent
  while read -r pid; do
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "tmux: server" ] && return 0
    parent=$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)
    [ -n "$parent" ] && [ "$(cat "/proc/$parent/comm" 2>/dev/null)" = "tmux: server" ] && return 0
  done <"$1"
  return 1
}

if ! units=$(systemctl --user list-units --type=scope --all --plain --no-legend 'tmux-spawn-*.scope'); then
  event_log_note tmux_hooks "FAILED to list the pane scopes for $sock"
  echo "reap-panes.sh: systemctl --user could not list the pane scopes" >&2
  exit 1
fi
units=$(awk '{print $1}' <<<"$units")

# No answer is a server gone, or one that cannot be reached: ours sorts those.
server=$(tmux -S "$sock" display-message -p '#{pid}' 2>/dev/null) || server=""

# Several sessions closing at once run several of these side by side, so a
# unit can go between the listing and any step here: one no longer up is
# skipped (and one up whose processes cannot be read fails, see no_procs).
for unit in $units; do
  if ! procs_file=$(procs_of "$unit"); then
    unit_up "$unit" && no_procs "$unit"
    continue
  fi
  ours "$unit" "$procs_file" || continue
  holds_pane "$procs_file" && continue
  procs=$(xargs -r ps -o pid=,args= -p <"$procs_file" 2>/dev/null | tr -s ' \n' ' ' | cut -c1-300)
  if systemctl --user stop "$unit" 2>/dev/null; then
    event_log_note tmux_hooks "reaped $unit:${procs:- (empty)}"
  elif unit_up "$unit"; then
    event_log_note tmux_hooks "FAILED to stop $unit:${procs:- (empty)}"
    echo "reap-panes.sh: could not stop $unit (holding:${procs:- nothing listed}); see: systemctl --user status $unit" >&2
    exit 1
  fi
done
