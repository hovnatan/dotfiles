#!/usr/bin/env bash
# check.sh covers: home/.config/fish/functions/tmux_attach_requested.fish home/.config/fish/config.fish scripts/lib/iterm2_ssh_arrangement.py scripts/lib/*
# The far side of a restored iTerm2 ssh arrangement's attach line, end to
# end but for the network: the line attach_line writes, typed into a local
# fish, reaches a login fish's config.fish through a stub ssh that passes on
# only what -o SendEnv names, as sshd does; tmux is a stub that records its
# argv and environment:
#
#   attach_line(...) --fish--> stub ssh --SendEnv vars only--> fish --login -i
#     --> config.fish --> tmux_attach_requested --exec--> stub tmux --> argv file
#                                                  `--> event log line
#
# Then the function's refusals (malformed, unknown socket, inside tmux, a
# log it cannot write), each of which leaves the shell and runs no tmux.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start tmux_attach_requested_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for cmd in fish python3; do
  command -v "$cmd" >/dev/null || {
    log "ERROR: $cmd is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done

# The far side's checkout: a copy of the fish config (fish writes its
# universal variables there) beside the repo's scripts, laid out as the
# function expects to find scripts/lib/event_log.sh from its own path. Its
# HOME is where the function's event log lands.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/remote/home/.config" "$work/home" "$work/bin"
cp -R "$REPO/home/.config/fish" "$work/remote/home/.config/fish"
ln -s "$REPO/scripts" "$work/remote/scripts"
fn=$work/remote/home/.config/fish/functions/tmux_attach_requested.fish
attach_log() { cat "$work"/home/.dotfiles/.logs/*_tmux_attach_requested/events.log 2>/dev/null; }

cat >"$work/bin/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$work/argv"
printf '%s\n' "\${LC_TMUX_ATTACH-unset}" >"$work/env"
EOF
# The stub ssh: options up to the destination, a remote command refused (the
# attach line must have none), and the login fish given only the variables
# SendEnv named.
cat >"$work/bin/ssh" <<EOF
#!/usr/bin/env bash
send=()
while [ \$# -gt 0 ]; do
  case \$1 in
    -o) [[ \$2 == SendEnv=* ]] && send+=("\${2#SendEnv=}"); shift 2 ;;
    -p) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
[ \$# -eq 1 ] || { echo "stub ssh: a remote command: \${*:2}" >&2; exit 2; }
fwd=()
for v in "\${send[@]}"; do [ -n "\${!v+x}" ] && fwd+=("\$v=\${!v}"); done
exec env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" "\${fwd[@]}" \
  fish --login -i -c 'echo shell-stayed' </dev/null
EOF
chmod +x "$work/bin/tmux" "$work/bin/ssh"

fails=0
check() {
  if [ "$2" = "$3" ]; then
    log "ok    $1"
  else
    log "FAIL  $1: got '$2', want '$3' (output: ${out-}; stderr: $(cat "$work/err" 2>/dev/null))"
    fails=$((fails + 1))
  fi
}
has() {
  case $2 in *"$3"*) log "ok    $1" ;; *)
    log "FAIL  $1: '$3' not in: $2"
    fails=$((fails + 1))
    ;;
  esac
}
recorded() { cat "$work/$1" 2>/dev/null || echo none; }

# --- the attach line, end to end ----------------------------------------------

# The lines the arrangement writes, one per socket it knows, from the
# script itself (with the stub iterm2 module its own test uses), so the
# writer and this reader cannot drift apart unseen.
lines=$(
  python3 - "$REPO" <<'PY'
import importlib.util, sys, types
stub = types.ModuleType("iterm2")
vars(stub).update({n: type(n, (), {}) for n in ("App", "Connection", "Session", "Window")})
sys.modules["iterm2"] = stub
spec = importlib.util.spec_from_file_location("arr", sys.argv[1] + "/scripts/lib/iterm2_ssh_arrangement.py")
arr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arr)
for socket in arr.SOCKETS:
    print(socket, arr.attach_line("ssh -p 2222 vm", socket, "api/docs"))
PY
)
[ -n "$lines" ] || {
  log "FAIL  attach_line gave no lines"
  exit 1
}
while read -r socket line; do
  rm -f "$work/argv" "$work/env"
  # stdout only: the throwaway HOME has no fisher, and plugins.fish says so.
  out=$(env -u LC_TMUX_ATTACH PATH="$work/bin:$PATH" fish --no-config -c "$line" 2>"$work/err") || true
  want="attach -t =api/docs"
  [ "$socket" = default ] || want="-L $socket $want"
  check "$socket: '$line' execs tmux $want" "$(recorded argv)" "$want"
  check "$socket: the request is erased before exec" "$(recorded env)" unset
  check "$socket: the login shell is replaced, not left" "$out" ""
  has "$socket: the exec is logged" "$(attach_log)" "LC_TMUX_ATTACH='$socket:api/docs' on"
done <<<"$lines"

# config.fish runs it for a login shell only: a fish started by hand with
# the variable set does not attach.
rm -f "$work/argv"
out=$(env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" LC_TMUX_ATTACH=default:main \
  fish -i -c 'echo shell-stayed' </dev/null 2>/dev/null)
check "a non-login fish runs no tmux" "$(recorded argv)" none
check "and goes on" "$out" shell-stayed

# --- refusals -------------------------------------------------------------------

# refuse <label> <value> <want in stderr> [<env>...]: the function under a
# bare fish refuses: status 1, no tmux, the reason on stderr and in the log.
refuse() {
  local label=$1 value=$2 want=$3
  shift 3
  rm -f "$work/argv"
  out=$(env HOME="$work/home" PATH="$work/bin:$PATH" LC_TMUX_ATTACH="$value" "$@" \
    fish --no-config -c "source $fn; tmux_attach_requested; echo status=\$status" 2>&1) || true
  check "$label: runs no tmux" "$(recorded argv)" none
  check "$label: fails" "${out##*status=}" 1
  has "$label: says why" "$out" "$want"
}
refuse "'main'" main "want <socket>:<session>"
refuse "'claude:'" claude: "want <socket>:<session>"
refuse "''" "" "want <socket>:<session>"
refuse "':main'" :main "socket '' is neither claude nor default"
refuse "'-S/tmp/x:main'" -S/tmp/x:main "socket '-S/tmp/x' is neither"
refuse "inside tmux" claude:x "inside tmux" TMUX=/tmp/tmux-1/default,1,0
has "refusals are logged" "$(attach_log)" "LC_TMUX_ATTACH='main' refused: want <socket>:<session>"

# A request it cannot log is not run: .logs is a file, so no directory.
mkdir -p "$work/nolog/.dotfiles"
: >"$work/nolog/.dotfiles/.logs"
rm -f "$work/argv"
out=$(env HOME="$work/nolog" PATH="$work/bin:$PATH" LC_TMUX_ATTACH=default:main \
  fish --no-config -c "source $fn; tmux_attach_requested; echo status=\$status" 2>&1) || true
check "an unwritable log: runs no tmux" "$(recorded argv)" none
check "an unwritable log: fails" "${out##*status=}" 1
has "an unwritable log: says so" "$out" "could not write the event log"

# No request: nothing happens, success.
rm -f "$work/argv"
out=$(env -u LC_TMUX_ATTACH HOME="$work/home" PATH="$work/bin:$PATH" \
  fish --no-config -c "source $fn; tmux_attach_requested; echo status=\$status" 2>&1)
check "no request is a no-op" "$out" status=0
check "no request runs no tmux" "$(recorded argv)" none

[ "$fails" -eq 0 ] || {
  log "FAILED: $fails checks"
  exit 1
}
log "all checks passed"
