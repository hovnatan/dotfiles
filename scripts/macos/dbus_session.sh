#!/usr/bin/env bash
#
# dbus_session.sh -- a D-Bus session bus for this login, which macOS does
# not have. Run by launchd (home/Library/LaunchAgents/
# com.hovnatan.dbus-session.plist), which starts it again if it crashes.
#
#   launchd --> dbus_session.sh --exec--> dbus-daemon, listening on ~/.cache/bus
#                                              ^                   ^
#                  zathura: registers as org.pwmt.zathura.PID-<pid>|
#                  scripts/appearance.sh: dbus-send, "set recolor-..." to each
#
# Why ~/.cache/bus: GLib programs (zathura) look for the session bus in
# DBUS_SESSION_BUS_ADDRESS, then at $XDG_RUNTIME_DIR/bus, and without an
# XDG_RUNTIME_DIR, as on macOS, that directory is ~/.cache. A socket there
# is found by every program however it was started (Finder, a shell,
# Zotero), with no environment variable to hand around. The launchd socket
# that the dbus package's own agent offers is only known to libdbus, which
# GLib does not use; that agent also fails here, for want of
# /etc/dbus-1/session.conf.
#
# Logs to ~/.dotfiles/.logs/<UTC>_dbus_session/events.log
# (scripts/lib/event_log.sh): one line at the start, then whatever
# dbus-daemon reports.

set -euo pipefail

[ "$(uname)" = "Darwin" ] || {
  echo "dbus_session.sh: macOS only; Linux has a session bus" >&2
  exit 1
}

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/../lib/event_log.sh"
# No prune from here: the bus must not come up later for one, or not at all.
event_log_start dbus_session --no-prune

daemon="$HOME/.nix-profile/bin/dbus-daemon"
conf="$HOME/.nix-profile/share/dbus-1/session.conf"
bus="$HOME/.cache/bus"
[ -x "$daemon" ] || {
  log "ERROR $daemon missing: apply the Nix package set (dotup), then re-run ~/.dotfiles/scripts/setup_user_symlinks.sh"
  exit 1
}
[ -f "$conf" ] || {
  log "ERROR $conf missing: the dbus package changed its layout; update dbus_session.sh"
  exit 1
}

mkdir -p "$HOME/.cache"
log "dbus-daemon on $bus"
exec "$daemon" --nofork --config-file="$conf" --address="unix:path=$bus" >>"$EVENT_LOG_FILE" 2>&1
