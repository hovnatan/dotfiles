#!/usr/bin/env bash
# prefix C-r (~/.tmux.conf): restart the claude in the session in view, in
# place -- `claude_tmux_run.sh restart`, behind a confirm popup that lists
# what the restart would kill (a turn, background shells, the processes the
# old claude left detached, by full path), one per line, with its verdict on
# the message line.
#
#   restart-claude.sh ask <socket path> <session> <client>   the binding
#   restart-claude.sh popup <text file>                      inside the popup
#
#   C-r --> ask: the claude socket? ---- no ---------> "not a claude session"
#                the client attached? -- no ---------> nothing (nobody to ask)
#           +--> big enough to ask? ---- no ---------> "too small"
#           |    restart --check ------- refused ----> its reason
#           |    all of it shown already? -- yes ----> restart --force
#           |    display-popup, blocking until it         |
#           |    closes; the popup shows the list    its last line
#           |    and takes one key:                       v
#           |      y: 10 ----+                       the message line
#           |      else: 3 --|-----------------------> nothing (cancelled)
#           |      any other |-----------------------> client gone: nothing;
#           +----------------+                         else "could not open"
#
# y is exit 10, never 0: tmux answers 0, drawing nothing, when it does not
# open a popup at all (another popup or a menu open on the client, a second
# C-r), which must not read as a yes. After a y the list is read again,
# under the session's current name (a /rename while the popup is open
# renames the tmux session): what started meanwhile -- a turn a Remote
# Control message began -- was never shown, so it is asked about first.
# The forced restart then kills only what the user saw (the pane shows
# whether a turn really runs: "busy" alone cannot tell).
#
# A popup, not confirm-before: a prompt is one status line, which cut the
# list (a full /nix/store path fills half of it), and its text goes through
# format and strftime expansion, so a background shell's `date +%s` showed
# as a number. The popup's text travels in a file, untouched by tmux and
# free of its 16 KB command limit, and the popup is a terminal: long lines
# wrap, and wide characters take their real width. Its size is fitted to
# the text and the title and capped at the client's (tmux refuses a bigger
# popup); each item is cut to 3 rows and the list to what fits, the full
# list a `restart --check` away. Only the title is a format, hence "#"
# doubled there.
#
# Only the claude socket (or the one a test names): elsewhere -- a default
# tmux server, a Mac, which has no claude socket -- claude_tmux_run.sh has
# no session to act on and its errors would only mislead. The restart logs
# every step under ~/.dotfiles/.logs/<UTC>_claude_tmux_restart/.
#
# A refusal is reported on the message line and exits 0: run-shell answers
# a non-zero exit by opening a "returned 1" view over the pane, which hides
# the message that says why.
set -u

# The popup's side: show the text (no newline after its last line, the key
# line, which so stays in view), take one key. C-c is a "no" too, not a
# failure to report.
if [ "${1:-}" = popup ] && [ $# -eq 2 ]; then
  trap 'exit 3' INT
  printf '%s' "$(<"$2")"
  read -rsn1 key
  [ "$key" = y ] && exit 10
  exit 3
fi

[ $# -eq 4 ] && [ "$1" = ask ] || {
  echo "usage: restart-claude.sh ask <socket path> <session> <client>" >&2
  exit 2
}
socket=$2 session=$3 client=$4
run="$HOME/.dotfiles/scripts/claude_tmux_run.sh"

say() { tmux -S "$socket" display-message -l -d 8000 -c "$client" "C-r: $1"; }
# client_size: "<width> <height>" of $client, empty once it is gone. A
# gone client is no error here, but display-message -c and its formats do
# not show it: for an unknown client they exit 0, falling back to some
# other client.
client_size() {
  tmux -S "$socket" list-clients -F '#{client_name} #{client_width} #{client_height}' \
    | awk -v c="$client" '$1 == c { print $2, $3 }'
}
# width <text>: display columns of its widest line (wc -L: an emoji is two).
width() { wc -L <<<"$1" | tr -d ' '; }
# rows <text> <inner width>: the rows it fills once wrapped at that width.
rows() {
  local line cols n=0
  while IFS= read -r line; do
    cols=$(width "$line")
    n=$((n + (cols == 0 ? 1 : (cols + $2 - 1) / $2)))
  done <<<"$1"
  echo "$n"
}
# cut_to <line> <columns>: the line cut to fit that many columns, "..."
# last. Cut by characters, then to half as many should wide ones still
# overflow (none is wider than two columns).
cut_to() {
  local line=$1 max=$(($2 - 3))
  if [ "$(width "$line")" -le "$2" ]; then
    echo "$line"
    return
  fi
  line=${line:0:max}
  [ "$(width "$line")" -le "$max" ] || line=${line:0:max/2}
  echo "$line..."
}

if [ "${socket##*/}" != "${CLAUDE_TMUX_SOCKET:-claude}" ]; then
  say "not a claude session (tmux socket ${socket##*/}); nothing to restart"
  exit 0
fi
export CLAUDE_TMUX_SOCKET="${socket##*/}"

# The session by id, which a rename leaves alone.
sid=$(tmux -S "$socket" list-sessions -F '#{session_name}'$'\t''#{session_id}' \
  | awk -F'\t' -v s="$session" '$1 == s { print $2 }')
if [ -z "$sid" ]; then
  say "session $session is gone; nothing to restart"
  exit 0
fi
textfile=$(mktemp "${TMPDIR:-/tmp}/restart-claude.XXXXXX") || exit 0
trap 'rm -f "$textfile"' EXIT

shown="" note=""
while :; do
  read -r cw ch < <(client_size)
  [ -n "${cw:-}" ] || exit 0
  if ! session=$(tmux -S "$socket" display-message -p -t "$sid" '#{session_name}' 2>/dev/null); then
    say "the session is gone; nothing restarted"
    exit 0
  fi
  if ! kills=$("$run" restart --check "$session" 2>&1); then
    say "$(tail -n 1 <<<"$kills")"
    exit 0
  fi

  # After a y: everything listed now was in the popup the user said y to,
  # so restart. Anything else -- all of it, before the first popup -- is
  # asked about. (An empty line in $shown matches only empty lines.)
  if [ -n "$note" ] && { [ -z "$kills" ] || ! grep -vxqF -f <(printf '%s\n' "$shown") <<<"$kills"; }; then
    break
  fi

  # The popup's text, each line indented a column off the border:
  #    The restart kills:
  #      background shell: sleep 900
  #      detached: /usr/bin/ssh
  #
  #    y: restart   any other key: cancel
  # Its width: the widest line or the title, whichever is wider, plus a
  # column of air and the border, capped at the client's. Each item is cut
  # to 3 rows of it, and the items to the rows left once the rest (border,
  # heading, blank, key line, and the hint for when anything is cut) has
  # its own; what does not fit is counted instead, on a row kept for that.
  title=" restart claude in $session? "
  key=" y: restart   any other key: cancel"
  hint=" full list: ${run/#"$HOME"/\~} restart --check $session"
  if [ -n "$kills" ]; then
    head=" ${note:+$note }The restart kills:"
    items="   ${kills//$'\n'/$'\n'   }"
  else
    head=" ${note:+$note }Nothing else is running; the restart kills nothing."
    items=""
  fi
  w=$(($(width "$head"$'\n'"$items"$'\n'"$key") + 3))
  [ "$w" -ge $(($(width "$title") + 4)) ] || w=$(($(width "$title") + 4))
  [ "$w" -le "$cw" ] || w=$cw
  iw=$((w - 2))
  room=$((ch - 2 - $(rows "$head" "$iw") - 1 - $(rows "$key" "$iw") - $(rows "$hint" "$iw")))
  if [ "$iw" -lt 10 ] || [ "$room" -lt 1 ]; then
    say "too small for the confirm popup (${cw}x$ch); nothing restarted"
    exit 0
  fi
  body="" cut=""
  if [ -n "$items" ]; then
    total=$(wc -l <<<"$items") n=0 used=0
    while IFS= read -r line; do
      n=$((n + 1))
      short=$(cut_to "$line" $((3 * iw)))
      [ "$short" = "$line" ] || cut=1
      r=$(rows "$short" "$iw")
      if [ $((used + r + (n < total ? 1 : 0))) -gt "$room" ]; then
        body+="   ... and $((total - n + 1)) more"$'\n'
        cut=1
        break
      fi
      body+="$short"$'\n'
      used=$((used + r))
    done <<<"$items"
  fi
  text="$head"$'\n'"$body"
  [ -z "$cut" ] || text+="$hint"$'\n'
  text+=$'\n'"$key"
  h=$(($(rows "$text" "$iw") + 2))
  [ "$h" -le "$ch" ] || h=$ch
  printf '%s' "$text" >"$textfile"

  # The command runs in tmux's default-shell, fish included. A heavy yellow
  # border (the message line's colour), set here rather than in the
  # popup-border-* options, so other popups keep theirs: the default thin
  # line in the terminal's colour is lost among claude's own boxes.
  err=$(tmux -S "$socket" display-popup -c "$client" -E -w "$w" -h "$h" -T "${title//#/##}" \
    -b heavy -S fg=yellow,bold "$(printf '%q popup %q' "$0" "$textfile")" 2>&1)
  rc=$?
  case $rc in
    10) ;;
    3) exit 0 ;;
    *)
      [ -n "$(client_size)" ] || exit 0
      say "could not open the confirm popup (rc $rc${err:+: $err}; another popup or menu open?); nothing restarted"
      exit 0
      ;;
  esac
  shown=$kills
  note="(changed since you answered)"
done

# The verdict is the restart's last line, its log stamp dropped.
say "restarting claude in $session ..."
out=$("$run" restart --force "$session" 2>&1)
say "$(tail -n 1 <<<"$out" | sed 's/^[0-9]*-[0-9]*-[0-9]*T[0-9:]*Z //')"
