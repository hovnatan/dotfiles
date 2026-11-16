#!/usr/bin/env bash
# periodic.sh -- run the recurring tasks that are due. launchd starts it
# every hour and at login (home/Library/LaunchAgents/com.hovnatan.periodic.plist);
# run it by hand to catch up now.
#
#   launchd, hourly --> periodic.sh
#     for each task in <repo>/scripts/periodic/*.sh of
#         ~/.dotfiles, ~/.dotfiles-private, ~/.hov-dotfiles-private
#       due?  now - last success >= its `# period:`     (never run: due)
#         no  -> skip, silently
#         yes -> run it under its `# timeout:` (default 1h)
#                  ok   -> record the success; if it was failing, notify "recovered"
#                  fail -> keep its output beside the event log; notify on the
#                          first failure only; it stays due, so the next hour
#                          retries it
#
# A task is an executable script whose header says how often it runs, and
# optionally how long it may take (s, m, h, d or w):
#
#   #!/usr/bin/env bash
#   # period: 7d
#   # timeout: 30m
#   exec "$HOME/.dotfiles/scripts/atuin_import_remote.sh" <host>
#
# Due is measured from the last success, not a calendar slot, so a Mac asleep
# or off past a due time runs the task once at the next hourly check, and a
# failing one is retried hourly until it passes. Tasks naming a host or an
# internal document go in a private repo's scripts/periodic/ (AGENTS.md).
#
# State: ${XDG_STATE_HOME:-~/.local/state}/periodic/<task>.last_ok (epoch
# seconds of the last success) and <task>.failing (present while it fails).
# Delete a .last_ok to make the task due now.
# Log: ~/.dotfiles/.logs/<UTC day>_periodic/events.log, a line per run or
# failure, with each failed run's output beside it as <HHMMSS>_<task>.log.
# Exit: 0 when every due task passed, 1 when any failed or was malformed.

set -uo pipefail

[ "${BASH_VERSINFO[0]}" -ge 4 ] || {
  echo "periodic.sh: needs bash 4+, got $BASH_VERSION; launchd must put Nix's bash first on PATH (the plist does)" >&2
  exit 1
}

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/lib/event_log.sh"
event_log_daily periodic || exit 1
LOG_DIR=$(dirname "$EVENT_LOG_FILE")

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/periodic
mkdir -p "$STATE"
TASK_DIRS=(
  "$HOME/.dotfiles/scripts/periodic"
  "$HOME/.dotfiles-private/scripts/periodic"
  "$HOME/.hov-dotfiles-private/scripts/periodic"
)
DEFAULT_TIMEOUT=3600

# notify <title> <message>: a desktop notification. Through argv, so quotes
# in a message cannot break the AppleScript.
notify() {
  if [ "$(uname)" = Darwin ]; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$1" "$2" >/dev/null \
      || log "ERROR notification failed: $1: $2"
  else
    notify-send "$1" "$2" || log "ERROR notification failed (notify-send): $1: $2"
  fi
}

status=0
# problem <message>: a task that cannot be run as written; always notified,
# since nothing else would ever show it.
problem() {
  log "ERROR $1"
  notify "periodic: task problem" "$1"
  status=1
}

# seconds <duration>: 30s -> 30, 90m -> 5400, 7d -> 604800; empty for
# anything else.
seconds() {
  [[ $1 =~ ^([0-9]+)([smhdw])$ ]] || return 0
  local n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]} in
    s) echo "$n" ;;
    m) echo $((n * 60)) ;;
    h) echo $((n * 3600)) ;;
    d) echo $((n * 86400)) ;;
    w) echo $((n * 604800)) ;;
  esac
}

# when <epoch>: 1794000000 -> "2026-11-06 16:20", 0 -> "never". BSD date
# reads an epoch with -r, GNU date with -d @.
when() {
  if [ "$1" -eq 0 ]; then
    echo never
  elif [ "$(uname)" = Darwin ]; then
    date -r "$1" '+%Y-%m-%d %H:%M'
  else
    date -d "@$1" '+%Y-%m-%d %H:%M'
  fi
}

# header <file> <key>: the value of a `# key: value` line in the first 20.
header() {
  head -n 20 "$1" | sed -n "s/^# $2: *\([^ ]*\) *\$/\1/p" | head -n 1
}

command -v gtimeout >/dev/null || {
  problem "gtimeout not on PATH (coreutils-prefixed, nix/flake.nix); no task runs without a time limit"
  exit 1
}

# One runner at a time: an hourly start while a long task still runs (or a
# hand run) leaves. A lock whose owner died is taken over.
lock="$STATE/.lock"
if ! mkdir "$lock" 2>/dev/null; then
  owner=$(cat "$lock/pid" 2>/dev/null)
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    log "another run (pid $owner) is still going; leaving"
    exit 0
  fi
  log "taking over the lock of pid ${owner:-?}, which is gone"
fi
echo $$ >"$lock/pid"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "$lock"' EXIT

# Collect the tasks: name -> file. A missing directory is a repo this
# machine does not have (the private ones are optional); a name in two
# repos is ambiguous state, refused.
declare -A tasks=()
for dir in "${TASK_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.sh; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .sh)
    if [ -n "${tasks[$name]:-}" ]; then
      problem "task '$name' is in two places, $f and ${tasks[$name]}; rename one"
      continue
    fi
    tasks[$name]=$f
  done
done

now=$(date +%s)
for name in $(printf '%s\n' "${!tasks[@]}" | sort); do
  f=${tasks[$name]}
  period=$(seconds "$(header "$f" period)")
  timeout=$(header "$f" timeout)
  if [ -z "$period" ]; then
    problem "$f: no valid '# period: <n>s|m|h|d|w' line in its first 20"
    continue
  fi
  if [ -n "$timeout" ]; then
    limit=$(seconds "$timeout")
    [ -n "$limit" ] || {
      problem "$f: '# timeout: $timeout' is not <n>s|m|h|d|w"
      continue
    }
  else
    limit=$DEFAULT_TIMEOUT
  fi
  [ -x "$f" ] || {
    problem "$f is not executable (chmod +x)"
    continue
  }

  last=0
  [ -f "$STATE/$name.last_ok" ] && last=$(cat "$STATE/$name.last_ok")
  [ $((now - last)) -ge "$period" ] || continue

  # Due: run it, its output to a file that only a failure keeps.
  log "run $name (every $(header "$f" period), last ok: $(when "$last"))"
  out="$tmp/$name.log"
  start=$(date +%s)
  gtimeout --kill-after=30 "$limit" "$f" >"$out" 2>&1 </dev/null
  rc=$?
  took=$(($(date +%s) - start))

  if [ "$rc" -eq 0 ]; then
    date +%s >"$STATE/$name.last_ok.tmp" && mv "$STATE/$name.last_ok.tmp" "$STATE/$name.last_ok"
    log "ok $name (${took}s)"
    if [ -e "$STATE/$name.failing" ]; then
      rm -f "$STATE/$name.failing"
      notify "periodic: $name recovered" "passed after failing"
    fi
    continue
  fi

  status=1
  kept="$LOG_DIR/$(date -u +%H%M%S)_$name.log"
  mv "$out" "$kept"
  why="exit $rc"
  [ "$rc" -eq 124 ] && why="timed out after ${timeout:-1h}"
  log "FAIL $name ($why, ${took}s); output: $kept"
  if [ ! -e "$STATE/$name.failing" ]; then
    : >"$STATE/$name.failing"
    notify "periodic: $name failed" "$why: $(grep -v '^\s*$' "$kept" | tail -n 1 | cut -c1-200)"
  fi
done

exit "$status"
