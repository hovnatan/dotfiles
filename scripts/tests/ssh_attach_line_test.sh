#!/usr/bin/env bash
# check.sh covers: scripts/lib/tmux_arrangement.py scripts/lib/ssh_command.py scripts/tests/ssh_attach_line_test.sh
# A restored tmux arrangement's ssh lines, end to end but for the network:
# the line attach_line writes, typed into a local fish, reaches the far side
# as the remote command sshd runs, and that runs tmux with the right
# arguments. ssh and tmux are stubs; the stub ssh refuses a line without -t
# (tmux needs a tty) and runs the remote command through `sh -c`, as sshd
# hands it to the login shell's -c:
#
#   attach_line(...) --fish--> stub ssh --remote command--> sh -c
#     --> stub tmux --> argv file
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start ssh_attach_line_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for cmd in fish python3; do
  command -v "$cmd" >/dev/null || {
    log "ERROR: $cmd is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$work/argv"
STUB
# Options up to the destination (-p and -o take an argument), then the
# remote command, which must be there and must have asked for a tty.
cat >"$work/bin/ssh" <<STUB
#!/usr/bin/env bash
tty=
while [ \$# -gt 0 ]; do
  case \$1 in
    -t) tty=1; shift ;;
    -p | -o) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
[ -n "\$tty" ] || { echo "stub ssh: no -t" >&2; exit 2; }
[ \$# -ge 2 ] || { echo "stub ssh: no remote command" >&2; exit 2; }
shift
exec sh -c "\$*"
STUB
chmod +x "$work/bin/tmux" "$work/bin/ssh"

fails=0
check() {
  if [ "$2" = "$3" ]; then
    log "ok    $1"
  else
    log "FAIL  $1: got '$2', want '$3' (stderr: $(cat "$work/err" 2>/dev/null))"
    fails=$((fails + 1))
  fi
}

# The lines from tmux_arrangement.py itself, so the writer and this reader
# cannot drift apart unseen: one per socket form, with and without a -t of
# the login's own.
lines=$(python3 -c 'import sys
sys.path.insert(0, sys.argv[1] + "/scripts/lib")
import tmux_arrangement
for login in ("ssh -p 2222 vm", "ssh -t vm"):
    for socket in ("default", "work"):
        print(socket, tmux_arrangement.attach_line(login, socket, "api/docs"))' "$REPO")
[ "$(wc -l <<<"$lines")" -eq 4 ] || {
  log "FAIL  attach_line gave no four lines: $lines"
  exit 1
}
while read -r socket line; do
  rm -f "$work/argv"
  PATH="$work/bin:$PATH" fish --no-config -c "$line" 2>"$work/err" || true
  want="attach -t =api/docs"
  [ "$socket" = default ] || want="-L $socket $want"
  check "'$line' runs tmux $want" "$(cat "$work/argv" 2>/dev/null || echo none)" "$want"
done <<<"$lines"

[ "$fails" -eq 0 ] || {
  log "FAILED: $fails checks"
  exit 1
}
log "all checks passed"
