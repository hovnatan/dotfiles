# Plan: extra tmux windows in claude sessions

Written 2026-10-28 on vm. Status: **planned, not started.** Nothing below is
implemented. Weigh it against the existing iTerm2-tabs workflow first (last
section).

Goal: open nvim and plain shells as extra tmux windows inside a claude
session (`tmux -L claude`), without losing navigation, notifications or the
cleanup of what a pane leaves behind. Four parts, landed together, each with
its tests.

## What already works with extra windows

- `claude_pane` (`scripts/claude_tmux_run.sh`) searches every window of a
  session, so `status`, `restart` and `prefix C-r` find claude wherever it
  is -- while claude runs. A session whose claude has exited is part 4.
- `restart` respawns only the claude pane; other windows are untouched.
- `sync-session-name.sh` ignores shell and nvim pane titles (no glyph).
- A bell in a background tmux window still reaches the terminal
  (`bell-action any`).

## 1. Window support (`home/.tmux.conf`)

Applies to every socket: invisible until a session has a second window.

- Bindings, all unbound today (`prefix c` stays "new session"):
  - `prefix C`: `new-window -c "#{pane_current_path}"`
  - `prefix n` / `prefix p`: next / previous window
  - `prefix 0`-`9`: select window; claude stays window 0
  - `prefix l`: last window
  - `prefix w`: `choose-tree -Zw`
  - `renumber-windows on`
- Indicator: the status bar is on for a session only while it has more than
  one window. `window-linked` / `window-unlinked[1]` hooks set the session's
  `status` on or off. It shows only the window list (`0:claude 1:nvim
  2:fish`), gruvbox, the current window in the border orange, bells in red.
- Verify while building: which session the hooks target, and what
  `window-unlinked` does mid-`kill-session` (the session is going away).

## 2. Reap per pane, not per session

`reap-panes.sh` logic is unchanged; only its triggers grow. Today it runs on
`session-closed` and at cold start, so a detached job from a closed pane
lives until some unrelated session closes.

Which hook fires for which close (tested 2026-10-28, tmux 3.7c):

| Pane closed by | Hook that fires |
| --- | --- |
| its program exits | `pane-exited` |
| `kill-pane` (window survives) | `after-kill-pane` |
| `kill-window` | `window-unlinked` (`after-kill-window` is not a hook) |
| `kill-session` / `claude_tmux_run.sh stop` | `window-unlinked`, `session-closed` |
| `restart` (remain-on-exit + respawn) | `pane-died` only, so no reap |
| server gone | none; cold start's `--server-gone` pass |

- Add `pane-exited`, `after-kill-pane` and `window-unlinked[0]` running the
  reaper; keep `session-closed` and the cold-start pass as the backstop.
- Keep the whole-server diff ("every scope with no live pane process")
  rather than targeting the closed pane: by hook time the pane's pid is gone,
  so its scope cannot be read from `/proc`, and the diff picks exactly that
  scope plus any leftovers.
- Restart stays safe: a concurrent reap can only stop the old claude's scope
  once its process has exited, which restart does anyway (and it treats an
  already-unloaded scope as success); the new claude's scope is born after
  the reaper's unit listing, so it is never a candidate.
- Header of `reap-panes.sh`: trigger diagram, "what a pane starts ends
  with it".

## 3. ntfy: watched means claude's pane is on screen

`home/.claude/ntfy-stop.sh` counts a session as watched when any focused,
recently active client is attached, so typing in nvim in window 2 cancels
the push for a turn finished in window 0.

- Hook mode reads `$TMUX_PANE` and passes it to the waiter beside the
  session id. A missing `$TMUX_PANE` inside tmux fails loudly.
- `watched()` resolves the pane's window on every poll (`break-pane` /
  `join-pane` move panes) and adds to its `list-clients -f` filter: the
  client's current window is that window, and the window is not zoomed onto
  another pane. The current window is per session in tmux, so all clients
  of a session agree.
- Pane gone: status 2, like a gone session.
- The "unwatched" log line names the window the client was on.

## 4. Bring claude back into a live session

Today claude exiting (`/exit`, a crash, an OOM kill) closes its pane, and
with it the session. With an nvim or shell window beside it the session
survives without claude, a state no command handles (read 2026-10-28):

| Command | Session alive, claude gone (today) |
| --- | --- |
| `load <name>` | **false success**: the bare-name branch sets `ok=1` on session existence and prints "already running" |
| `load <name>/<task>`, `--id` | refuses, "stop it first", which kills the other windows |
| `restart`, `prefix C-r` | refuses, "stop, then load", which kills the other windows |
| `new <name>` | refuses (the name is live); correct, keep it |
| `serve` (the manager) | **never recovers**: the watcher waits only for the session to vanish, so systemd never resumes claude |
| `status` | correct: "NO CLAUDE -- pane runs fish" |

- `load`: "already running" means a claude pane (`claude_pane`), not a
  session of that name. A live session without one gets the conversation
  resumed into a new window 0 of it: `launch` grows a
  `new-window -t =<name>:0` branch beside `new-session`, with the same
  `PANE_CMD`, directory and `--remote-control`. Index 0 may be taken by
  another window once claude's closed (`renumber-windows`); then
  `new-window -b` before the first window, so claude is 0 again. The
  label guards stay: `load <name>/<task>` and `--id` still refuse a live
  claude holding another conversation.
- `restart` with no claude: point at `load <name>`, not `stop` + `load`.
- `serve`: loop while the manager has a claude pane; a manager session
  left without one gets the manager resumed into it, as at boot.
- Header of `claude_tmux_run.sh` and the `load` section of
  `claude_tmux_session/AGENTS.md`: `load` also revives a session's claude.

## Tests

- `scripts/tests/tmux_hooks_test.sh`: status on at two windows, off at one;
  bindings present; a one-window session keeps `status off`.
- `scripts/tests/claude_tmux_run_test.sh`: a detached `sleep` in a second
  pane is reaped on each close path of the table; the claude pane's scope
  survives all of them; a `restart` racing another pane's close ends with
  the new claude up and no `FAILED to stop`; a three-window session close
  runs parallel reaps cleanly.
- `scripts/tests/claude_tmux_run_test.sh`, part 4: a session with a second
  window whose claude exits -> `load <name>` resumes claude as window 0 and
  the other window keeps its pid; `load <name>/<task>` and `--id` do the
  same for their conversation and still refuse a live claude holding
  another; `restart` with no claude names `load`; the manager's claude
  exiting beside an extra window is resumed by the `serve` watcher.
- `scripts/tests/ntfy_stop_test.sh` (it runs the hook with
  `env -u TMUX_PANE` today, so pass a real pane): focused on claude's window
  -> no push; focused on another window of the session -> push; claude's
  window zoomed onto a split -> push; no `$TMUX_PANE` -> loud failure.
- `scripts/check.sh` green.

## Docs

- `claude_tmux_session/AGENTS.md`, "The setup": "what a session starts ends
  with it" becomes per pane, with when; one line on windows (claude stays
  window 0; a second `claude` in the same session is unsupported, since both
  would rename the session).
- Header comments of `ntfy-stop.sh`, `reap-panes.sh` and the `.tmux.conf`
  hook block.

## Rollout

`tmux -L claude source-file ~/.tmux.conf` on each machine; running sessions
are untouched. `ntfy-stop.sh` takes effect at the next Stop.

## Out of scope

- extrakto and the `prefix v` snapshot see only the current window.
- `load` restores only claude's window; no tmux-resurrect.

## Compared with iTerm2 tabs

The iTerm2-tabs workflow already does what windows would, better integrated
with `home/.hammerspoon/iterm2_api.py`: a bell banner per tab not in view,
native tab switching, the middle-click window picker, Cmd-T for a shell on
the same host, and saved arrangements (`scripts/iterm2_ssh_arrangement.sh`).
A bell in a background tmux window would get no banner, because the iTerm2
tab holding it is the one in view. What tmux windows add is persistence of
the nvim and shell state across disconnects; a default-socket tmux session
in its own iTerm2 tab gives that without touching the claude sessions.
