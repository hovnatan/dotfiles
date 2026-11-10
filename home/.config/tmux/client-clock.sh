#!/usr/bin/env bash
# client-clock.sh <client pid> -- the date, time and zone for the tmux status
# bar (home/.config/tmux/tmux.conf, status-right), in the zone of the person
# looking at it rather than the tmux server's.
#
#   Mac (Asia/Yerevan)                     Linux VM, server in UTC
#   fish: LC_CLIENT_TZ=Asia/Yerevan  --ssh (SendEnv LC_*)-->  login fish
#   (conf.d/client_tz.fish)                                    |
#                                                         tmux attach (client pid 4242,
#                                                         LC_CLIENT_TZ in its environ)
#                                                              |
#   tmux server, per client, every status-interval:            v
#     #(client-clock.sh #{client_pid})  ->  /proc/4242/environ  ->  "10 Nov 18:05 +04"
#
# tmux draws the bar per client and keeps a client's #() jobs apart, and
# #{client_pid} makes each client's command distinct, so two clients of one
# session, attached from two zones, each see their own time.
#
#   LC_CLIENT_TZ=Asia/Yerevan       -> "10 Nov 18:05 +04"
#   no LC_CLIENT_TZ (a local tmux   -> the server's time, as strftime gave it
#   client, an ssh from elsewhere)     before: "10 Nov 14:05 UTC"
#   LC_CLIENT_TZ=Mars/Olympus       -> the reason in the bar, exit 1, a line
#                                      in the client_clock event log
#
# %Z stays in every form, so the bar always says which zone it shows.
#
# Limits:
#   - the zone is read from the client's environment at its start: it is the
#     one the ssh connection carried, so after travel only a new ssh (from a
#     fish started after the move) brings the new zone
#   - macOS shows no process's environment to another (ps -E prints none of
#     it), so a tmux server on a Mac shows its own time to every client; its
#     local clients are in that zone already
#
# tmux shows what this prints in place of the clock, so a failure is printed
# there. Only failures go to the event log: on success it acts on nothing,
# and it runs every 15 s per client (as status-stats.sh).
set -u

FORMAT='%d %b %H:%M %Z'

# fail <reason>: the reason in the bar and in today's log, exit 1
fail() {
  echo "clock: $1"
  # shellcheck source=scripts/lib/event_log.sh
  . "${0%/*}/../../../scripts/lib/event_log.sh" \
    && event_log_note client_clock "client ${pid:-?}: $1"
  exit 1
}

pid=${1:-}
case "$pid" in
  '' | *[!0-9]*) fail "usage: client-clock.sh <client pid>, got '${pid}'" ;;
esac

# The client's zone. Its environ is NUL-separated KEY=VALUE pairs; read with
# builtins, no fork. A client gone between the draw and this run leaves no
# file; tmux drops the output with the client.
zone=
if [ "$(uname)" = Linux ]; then
  environ=/proc/$pid/environ
  [ -r "$environ" ] || fail "cannot read $environ (client gone, or another user's)"
  while IFS= read -r -d '' kv; do
    case "$kv" in
      LC_CLIENT_TZ=*) zone=${kv#LC_CLIENT_TZ=} ;;
    esac
  done <"$environ"
fi

if [ -z "$zone" ]; then
  date "+$FORMAT"
  exit 0
fi

# A zone name glibc does not know is read as UTC with the name as its
# abbreviation ("Mars" shown as the zone, UTC time): a wrong time that looks
# right. So the name must be a file of the zone database.
zonedir=${TZDIR:-/usr/share/zoneinfo}
case "$zone" in
  /* | *..* | *[!A-Za-z0-9_+/-]*) fail "LC_CLIENT_TZ='$zone' is not a zone name like Asia/Yerevan" ;;
esac
[ -f "$zonedir/$zone" ] || fail "LC_CLIENT_TZ='$zone': no $zonedir/$zone"
TZ=$zone date "+$FORMAT"
