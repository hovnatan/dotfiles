#!/usr/bin/env bash
# tmux session-closed hook (declared in ~/.tmux.conf), and the first step of
# a cold start in scripts/claude_tmux_run.sh (launch): on the claude socket,
# stop the systemd scope of every pane that no longer exists, ending
# whatever a session left running in the background there.
#
#   reap-panes.sh <socket path> [--server-gone]
#
# Which pane a scope belongs to is read from its processes: every process
# started in a pane inherits TMUX_PANE (%N), detached ones included. A scope
# with a process whose TMUX_PANE is a live pane stays; any other is stopped.
# A scope that holds a live pane's own process stays too.
# So a pane's first process exiting is not enough -- `restart` respawns the
# pane (the same %N, a new claude in a new scope) and keeps the jobs the old
# claude left -- but the pane closing, with its session, is.
#
#   tmux-spawn-a.scope  claude (TMUX_PANE=%3), proxy (%3)   %3 live  -> kept
#   tmux-spawn-b.scope  proxy (TMUX_PANE=%1)                %1 gone  -> stopped
#   tmux-spawn-c.scope  a process without TMUX_PANE alone            -> stopped
#
# tmux 3.7 runs each pane in a scope of its own, PartOf the server's scope
# (see launch in scripts/claude_tmux_run.sh). A process a session detached
# -- setsid, nohup, a tool's background job -- stays in its pane's scope
# when the pane closes, so the scope stays active, and through PartOf it
# keeps the server's scope loaded even once the server has exited. The next
# cold start then cannot create tmux-server-<socket> again and nothing
# comes up (seen 2026-10-22, held by a cloud-sql-proxy):
#
#   tmux-server-claude.scope        inactive, dead: the server exited
#     ^ PartOf
#   tmux-spawn-<uuid>.scope         active: its pane is gone, but
#     `- cloud-sql-proxy ...        a session's background job is not
#
# So what a session started ends with it:
#
#   session-closed hook (~/.tmux.conf)  -> reap-panes.sh <socket>
#       every pane scope that holds no process of a live pane
#   launch, no server (claude_tmux_run.sh) -> reap-panes.sh <socket> --server-gone
#       all of them -- the hook cannot be relied on for the last session,
#       whose server exits with it -- then waits for the server's scope to
#       unload, and fails naming what still holds it
#   either, the server's scope up but tmux unable to reach it (socket file
#   removed, a tmux the server rejects) -> stops nothing, fails loudly
#
# A job meant to outlive its session belongs in a unit of its own:
#   systemd-run --user --unit=<name> <command>
#
# Each scope stopped is logged with what ran in it (the tmux hooks' log):
#   2026-10-22T19:36:30Z reaped tmux-spawn-7c10....scope: 2130207 cloud-sql-proxy --auto-iam-authn ...
set -u

sock=${1:?usage: reap-panes.sh <socket path> [--server-gone]}
server_gone=${2:-}
name=${sock##*/}
# Only the claude socket (or the one a test names): its server, and only
# its server, runs in tmux-server-<socket>.scope. And only under systemd:
# a Mac has no scopes, and its tmux leaves nothing like this behind.
[ "$name" = "${CLAUDE_TMUX_SOCKET:-claude}" ] || exit 0
command -v systemctl >/dev/null || exit 0
server_unit="tmux-server-$name.scope"

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"

# The pane scopes, listed BEFORE anything is asked of the server: a scope
# only exists once tmux has forked its pane, so every pane a listed scope
# can belong to is in the list-panes below. The other order stopped a pane
# born in between. Likewise a server started after this listing has its
# scope active by the time --server-gone checks it below.
units=$(systemctl --user show -p ConsistsOf --value "$server_unit")

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
# server_runs: true while the tmux server process is in its scope. Not the
# scope's own state: the hooks the server runs (this one included) live in
# that scope too and keep it up for a moment after the server has gone.
server_runs() {
  local f pid
  unit_up "$server_unit" || return 1
  f=$(procs_of "$server_unit") || no_procs "$server_unit"
  while read -r pid; do
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "tmux: server" ] && return 0
  done <"$f"
  return 1
}
# unreachable <client error>: the server runs and this cannot reach it --
# not the same as a server gone. Stop nothing.
unreachable() {
  event_log_note tmux_hooks "REFUSED to reap: the tmux server in $server_unit runs but $sock cannot reach it ($1)"
  echo "reap-panes.sh: no tmux server answers at $sock ($1), but one runs in $server_unit: it cannot be reached (its socket file removed? a tmux the server's protocol rejects?). Nothing stopped. Check: systemctl --user status $server_unit; ls -l $sock" >&2
  exit 1
}

# The live panes, " %0 %3 ", and the scopes their own processes run in,
# " tmux-spawn-a.scope ... " -- that one is how a pane just forked is known,
# before it execs into an environment that has TMUX_PANE. None once the
# server is gone. The scope is the last component of the unified (cgroup
# v2) line of /proc/<pid>/cgroup: "0::/user.slice/.../tmux-spawn-a.scope".
live=" " live_scopes=" "
if [ -n "$server_gone" ]; then
  server_runs && unreachable "no server answers"
else
  # A failed list-panes is never read as "no panes", which would stop every
  # pane's scope. The server exiting with its last session is the one
  # benign failure: it is gone within moments, and what it leaves
  # is the next cold start's (launch runs this with --server-gone).
  if ! out=$(tmux -S "$sock" list-panes -a -F '#{pane_id} #{pane_pid}' 2>&1); then
    for _ in $(seq 50); do
      server_runs || {
        event_log_note tmux_hooks "server gone with its last session; its pane scopes are the next start's to stop"
        exit 0
      }
      sleep 0.1
    done
    unreachable "$(tr '\n' ' ' <<<"$out")"
  fi
  while read -r pane pid; do
    live+="$pane "
    cg=$(sed -n 's/^0:://p' "/proc/$pid/cgroup" 2>/dev/null) && live_scopes+="${cg##*/} "
  done <<<"$out"
fi

# owned <cgroup.procs file>: true if a process listed there belongs to a
# live pane. environ is NUL-separated; a process gone meanwhile reads empty.
owned() {
  local pid pane
  while read -r pid; do
    pane=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^TMUX_PANE=//p')
    [ -n "$pane" ] && case $live in *" $pane "*) return 0 ;; esac
  done <"$1"
  return 1
}

# Several sessions closing at once run several of these side by side, so a
# unit can go between the listing and any step here: one no longer up is
# skipped (and one up whose processes cannot be read fails, see no_procs).
for unit in $units; do
  case $unit in tmux-spawn-*.scope) ;; *) continue ;; esac
  case $live_scopes in *" $unit "*) continue ;; esac
  if ! procs_file=$(procs_of "$unit"); then
    unit_up "$unit" && no_procs "$unit"
    continue
  fi
  owned "$procs_file" && continue
  procs=$(xargs -r ps -o pid=,args= -p <"$procs_file" 2>/dev/null | tr -s ' \n' ' ' | cut -c1-300)
  if systemctl --user stop "$unit" 2>/dev/null; then
    event_log_note tmux_hooks "reaped $unit:${procs:- (empty)}"
  elif unit_up "$unit"; then
    event_log_note tmux_hooks "FAILED to stop $unit:${procs:- (empty)}"
    echo "reap-panes.sh: could not stop $unit (holding:${procs:- nothing listed}); see: systemctl --user status $unit" >&2
    exit 1
  fi
done

[ -n "$server_gone" ] || exit 0
# A stopped transient unit is unloaded once nothing references it; the
# server's scope goes a moment after its last pane scope.
for _ in $(seq 50); do
  [ "$(systemctl --user show -p LoadState --value "$server_unit")" = loaded ] || exit 0
  sleep 0.1
done
echo "reap-panes.sh: $server_unit is still loaded ($(systemctl --user show -p ActiveState,ConsistsOf --value "$server_unit" | tr '\n' ' ')); a new tmux server cannot take its name. Inspect it with: systemctl --user status $server_unit" >&2
exit 1
