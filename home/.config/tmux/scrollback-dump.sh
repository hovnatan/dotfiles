#!/usr/bin/env bash
# Periodically dump full scrollback of every pane in a tmux session.
# Invoked from a session-created hook with:
#   #{session_id} #{session_name}
set -u

session_id="${1:?session id required}"
session_name="${2:?session name required}"

safe_name="${session_name//[^A-Za-z0-9._-]/_}"
start_ts="$(date +%Y%m%d-%H%M%S)"
dir="${HOME}/.local/share/tmux-scrollback/${safe_name}-${start_ts}"
mkdir -p "$dir"

tmux display-message -d 10000 -t "$session_id" "scrollback → $dir"

while tmux has-session -t "$session_id" 2>/dev/null; do
    while IFS=$'\t' read -r pane_id win_idx pane_idx; do
        [ -n "$pane_id" ] || continue
        tmux capture-pane -t "$pane_id" -pS -100000 \
            > "$dir/w${win_idx}p${pane_idx}.log" 2>/dev/null || true
    done < <(tmux list-panes -s -t "$session_id" \
        -F '#{pane_id}	#{window_index}	#{pane_index}' 2>/dev/null)
    sleep 600
done
