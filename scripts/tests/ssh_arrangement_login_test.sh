#!/usr/bin/env bash
# check.sh covers: home/.config/fish/functions/tmux_attach_requested.fish home/.config/fish/functions/login_dir_requested.fish home/.config/fish/functions/__ssh_arrangement_note.fish home/.config/fish/config.fish scripts/lib/iterm2_ssh_arrangement.py scripts/lib/*
# The far side of a restored iTerm2 ssh arrangement's lines, end to end but
# for the network: the line attach_line or dir_line writes, typed into a
# local fish, reaches a login fish's config.fish through a stub ssh that
# passes on only what -o SendEnv names, as sshd does; tmux is a stub that
# records its argv and environment:
#
#   attach_line(...) --fish--> stub ssh --SendEnv vars only--> fish --login -i
#     --> config.fish --> tmux_attach_requested --exec--> stub tmux --> argv file
#                                                  `--> event log line
#   dir_line(...)    --fish--> stub ssh --SendEnv vars only--> fish --login -i
#     --> config.fish --> login_dir_requested --cd--> `pwd` of the shell
#                                                `--> event log line
#
# Then each function's refusals (malformed, unknown socket, inside tmux, a
# log it cannot write; a relative or missing directory), each of which
# leaves the shell where it was and runs no tmux.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)

# Run from a tmux pane (any claude session, so every pre-push hook there),
# the inherited TMUX made each case take the "inside tmux" refusal and fail
# its own assertion. That refusal is tested on purpose below, with TMUX set
# explicitly; everything else is about a shell outside tmux.
unset TMUX TMUX_PANE
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start ssh_arrangement_login_test --no-prune
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
# Physical (macOS: /var is /private/var), as a shell started by env -i, with
# no PWD to keep, reports it so.
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/remote/home/.config" "$work/home" "$work/bin"
cp -R "$REPO/home/.config/fish" "$work/remote/home/.config/fish"
ln -s "$REPO/scripts" "$work/remote/scripts"
fns=$work/remote/home/.config/fish/functions
fn=$fns/tmux_attach_requested.fish
# What a bare fish (--no-config, so no autoload) sources to run each function.
helpers="source $fns/__ssh_arrangement_note.fish; source $fns/__ssh_arrangement_decode.fish"
attach_fns="$helpers; source $fn"
dir_fns="$helpers; source $fns/login_dir_requested.fish"
attach_log() { cat "$work"/home/.dotfiles/.logs/*_tmux_attach_requested/events.log 2>/dev/null; }
dir_log() { cat "$work"/home/.dotfiles/.logs/*_login_dir_requested/events.log 2>/dev/null; }

cat >"$work/bin/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$work/argv"
printf '%s\n' "\${LC_TMUX_ATTACH-unset}" >"$work/env"
printf tmux-started
EOF
# The stub ssh: options up to the destination, a remote command refused (the
# attach line must have none), and the login fish given only the variables
# SendEnv named, less any whose value holds a "/", which Tailscale SSH drops.
# LC_TERMINAL goes too, as macOS's ssh_config sends LC_*.
cat >"$work/bin/ssh" <<EOF
#!/usr/bin/env bash
send=(LC_TERMINAL)
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
for v in "\${send[@]}"; do
  [ -n "\${!v+x}" ] && [[ \${!v} != */* ]] && fwd+=("\$v=\${!v}")
done
exec env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" "\${fwd[@]}" \
  fish --login -i -c 'echo shell-stayed in \$PWD' </dev/null
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
# arrangement <python> [<arg>...]: run python with the script loaded as `arr`
# (and the stub iterm2 and websockets modules its own test uses); the args
# are `args`.
arrangement() {
  local code=$1
  shift
  python3 -c "import importlib.util, sys, types
stub = types.ModuleType('iterm2')
vars(stub).update({n: type(n, (), {}) for n in ('App', 'Connection', 'Session', 'Window')})
sys.modules['iterm2'] = stub
errors = types.ModuleType('websockets.exceptions')
vars(errors)['InvalidHandshake'] = type('InvalidHandshake', (Exception,), {})
sockets = types.ModuleType('websockets')
vars(sockets)['exceptions'] = errors
sys.modules.update({'websockets': sockets, 'websockets.exceptions': errors})
spec = importlib.util.spec_from_file_location('arr', sys.argv[1] + '/scripts/lib/iterm2_ssh_arrangement.py')
arr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arr)
args = sys.argv[2:]
$code" "$REPO" "$@"
}
lines=$(arrangement 'for socket in arr.SOCKETS:
    print(socket, arr.attach_line("ssh -p 2222 vm", socket, "api/docs"))')
[ -n "$lines" ] || {
  log "FAIL  attach_line gave no lines"
  exit 1
}
# From an iTerm2 tab: the host report goes out before tmux starts, while
# tmux's mouse, focus and paste modes are still off; iTerm2 resets them,
# with a banner each, on a host change that comes after.
while read -r socket line; do
  rm -f "$work/argv" "$work/env"
  # stdout only: the throwaway HOME has no fisher, and plugins.fish says so.
  out=$(env -u LC_TMUX_ATTACH -u TERM_PROGRAM LC_TERMINAL=iTerm2 PATH="$work/bin:$PATH" \
    fish --no-config -c "$line" 2>"$work/err") || true
  want="attach -t =api/docs"
  [ "$socket" = default ] || want="-L $socket $want"
  check "$socket: '$line' execs tmux $want" "$(recorded argv)" "$want"
  check "$socket: the request is erased before exec" "$(recorded env)" unset
  case $out in
    $'\e]1337;RemoteHost='*@*$'\a'tmux-started)
      log "ok    $socket: the host is reported, then tmux replaces the shell"
      ;;
    *)
      log "FAIL  $socket: want the host report, then tmux, and nothing else: $(printf '%q' "$out")"
      fails=$((fails + 1))
      ;;
  esac
  has "$socket: the exec is logged" "$(attach_log)" "LC_TMUX_ATTACH='$socket:api%2Fdocs' on"
done <<<"$lines"

# From another terminal: no report, as the prompt sends none there.
first_line=$(head -1 <<<"$lines" | cut -d' ' -f2-)
out=$(env -u LC_TMUX_ATTACH -u LC_TERMINAL PATH="$work/bin:$PATH" \
  fish --no-config -c "$first_line" 2>"$work/err") || true
check "not iTerm2: no host report, tmux replaces the shell" "$out" tmux-started

# config.fish runs it for a login shell only: a fish started by hand with
# the variable set does not attach.
rm -f "$work/argv"
out=$(env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" LC_TMUX_ATTACH=default:main \
  fish -i -c 'echo shell-stayed' </dev/null 2>/dev/null)
check "a non-login fish runs no tmux" "$(recorded argv)" none
check "and goes on" "$out" shell-stayed

# --- the directory line, end to end -------------------------------------------

# Directories holding what a path may, on the "far side" (this machine,
# under $work), and the lines the arrangement writes for them, from the
# script itself.
far=$work/far
dirs=("$far/it's here" "$far/a+b/%41/c d/"$'\xc3\xbc' "$far/x;\$y/\`z\`/~" "$far/a:b")
mkdir -p "${dirs[@]}"
dir_lines=$(arrangement 'for d in args:
    print(arr.dir_line("ssh -p 2222 vm", d))' "${dirs[@]}")
i=0
while read -r line; do
  d=${dirs[$i]}
  i=$((i + 1))
  label="dir $(printf %q "$d")"
  out=$(cd "$work" && env -u LC_LOGIN_DIR -u LC_TMUX_ATTACH PATH="$work/bin:$PATH" \
    fish --no-config -c "$line" 2>"$work/err") || true
  check "$label: the login shell lands there" "$out" "shell-stayed in $d"
  has "$label: the cd is logged, escaped" "$(dir_log)" "cd $(fish --no-config -c 'string escape -- $argv[1]' "$d")"
done <<<"$dir_lines"
check "every directory line was run" "$i" "${#dirs[@]}"

# config.fish runs it for a login shell only, and the request is not
# inherited by what the shell starts.
out=$(cd "$work" && env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" LC_LOGIN_DIR=%2F \
  fish -i -c 'echo $PWD' </dev/null 2>/dev/null)
check "a non-login fish does not cd" "$out" "$work"
out=$(cd "$work" && env -i HOME="$work/home" PATH="$work/bin:$PATH" TERM=dumb \
  XDG_CONFIG_HOME="$work/remote/home/.config" LC_LOGIN_DIR=%2F \
  fish --login -i -c 'echo $PWD; set -q LC_LOGIN_DIR; and echo kept; or echo erased' </dev/null 2>/dev/null)
check "a login fish cd's, and erases the request" "$out" $'/\nerased'

# refuse_dir <label> <value> <want in stderr>: the function under a bare
# fish refuses: status 1, the shell still where it started, the reason on
# stderr and in the log.
refuse_dir() {
  local label=$1 value=$2 want=$3
  out=$(cd "$work" && env HOME="$work/home" LC_LOGIN_DIR="$value" \
    fish --no-config -c "$dir_fns; login_dir_requested; echo status=\$status in \$PWD" 2>&1) || true
  check "$label: fails, staying put" "${out##*status=}" "1 in $work"
  has "$label: says why" "$out" "$want"
}
refuse_dir "a relative directory" home%2Fme "home/me is not an absolute path"
refuse_dir "an empty one" "" "'' is not an absolute path"
refuse_dir "a missing one" %2Fgone%2Fhere "/gone/here"
refuse_dir "a raw /" /srv "not %-encoded as the arrangement writes it"
refuse_dir "a bad escape" %zz%2Fa "not %-encoded as the arrangement writes it"
refuse_dir "a cut-off escape" %2Fa%2 "not %-encoded as the arrangement writes it"
# A newline, which the caller's (...) would split at, or drop at the end.
newline=$(arrangement 'print(arr.dir_line("ssh vm", "/a\nb"), arr.dir_line("ssh vm", "/a\n"))')
for line in $newline; do
  case $line in LC_LOGIN_DIR=*) refuse_dir "${line%% *}" "${line#LC_LOGIN_DIR=}" "a newline (%0A)" ;; esac
done
has "dir refusals are logged" "$(dir_log)" "LC_LOGIN_DIR='home%2Fme' refused"
has "a bad encoding is logged, escaped" "$(dir_log)" "LC_LOGIN_DIR='%zz%2Fa' refused: not %-encoded"
has "a failed cd is logged" "$(dir_log)" "cd /gone/here failed; staying in $work"

# A request it cannot log is not run, as for tmux: .logs is a file.
mkdir -p "$work/nolog/.dotfiles" "$far/unlogged"
: >"$work/nolog/.dotfiles/.logs"
out=$(cd "$work" && env HOME="$work/nolog" LC_LOGIN_DIR="$(arrangement 'from urllib.parse import quote; print(quote(args[0], safe=""))' "$far/unlogged")" \
  fish --no-config -c "$dir_fns; login_dir_requested; echo status=\$status in \$PWD" 2>&1) || true
check "an unwritable log: no cd, fails" "${out##*status=}" "1 in $work"
has "an unwritable log: says so" "$out" "could not write the event log"

# The save's directory check (dirs_argv), its remote word run by a login
# shell of either kind: one y or n per directory on stdin.
word=$(arrangement 'print(arr.dirs_argv("ssh vm", unattended=False)[-1])')
for shell in sh fish; do
  out=$(printf '%s\n' "$far/it's here" "$far/none" "$far/x;\$y/\`z\`/~" | "$shell" -c "$word")
  check "the directory check under $shell" "$out" $'y\nn\ny'
done

out=$(cd "$work" && env -u LC_LOGIN_DIR HOME="$work/home" \
  fish --no-config -c "$dir_fns; login_dir_requested; echo status=\$status in \$PWD" 2>&1)
check "no directory request is a no-op" "$out" "status=0 in $work"

# --- refusals -------------------------------------------------------------------

# refuse <label> <value> <want in stderr> [<env>...]: the function under a
# bare fish refuses: status 1, no tmux, the reason on stderr and in the log.
refuse() {
  local label=$1 value=$2 want=$3
  shift 3
  rm -f "$work/argv"
  out=$(env HOME="$work/home" PATH="$work/bin:$PATH" LC_TMUX_ATTACH="$value" "$@" \
    fish --no-config -c "$attach_fns; tmux_attach_requested; echo status=\$status" 2>&1) || true
  check "$label: runs no tmux" "$(recorded argv)" none
  check "$label: fails" "${out##*status=}" 1
  has "$label: says why" "$out" "$want"
}
refuse "'main'" main "want <socket>:<session>"
refuse "'claude:'" claude: "want <socket>:<session>"
refuse "''" "" "want <socket>:<session>"
refuse "':main'" :main "socket '' is neither claude nor default"
refuse "'-S%2Ftmp%2Fx:main'" -S%2Ftmp%2Fx:main "socket '-S/tmp/x' is neither"
refuse "a raw /" claude:api/docs "not %-encoded as the arrangement writes it"
refuse "a bad escape" claude:%zz "not %-encoded as the arrangement writes it"
refuse "inside tmux" claude:x "inside tmux" TMUX=/tmp/tmux-1/default,1,0
has "refusals are logged" "$(attach_log)" "LC_TMUX_ATTACH='main' refused: want <socket>:<session>"

# A request it cannot log is not run: .logs is a file, so no directory.
mkdir -p "$work/nolog/.dotfiles"
: >"$work/nolog/.dotfiles/.logs"
rm -f "$work/argv"
out=$(env HOME="$work/nolog" PATH="$work/bin:$PATH" LC_TMUX_ATTACH=default:main \
  fish --no-config -c "$attach_fns; tmux_attach_requested; echo status=\$status" 2>&1) || true
check "an unwritable log: runs no tmux" "$(recorded argv)" none
check "an unwritable log: fails" "${out##*status=}" 1
has "an unwritable log: says so" "$out" "could not write the event log"

# No request: nothing happens, success.
rm -f "$work/argv"
out=$(env -u LC_TMUX_ATTACH HOME="$work/home" PATH="$work/bin:$PATH" \
  fish --no-config -c "$attach_fns; tmux_attach_requested; echo status=\$status" 2>&1)
check "no request is a no-op" "$out" status=0
check "no request runs no tmux" "$(recorded argv)" none

[ "$fails" -eq 0 ] || {
  log "FAILED: $fails checks"
  exit 1
}
log "all checks passed"
