---
name: tmux-session
description: "Claude Code sessions in tmux: one opened in a folder, or a named conversation resumed in one. Load before creating, restarting or closing a tmux session that runs claude, or typing claude into a pane."
---

# tmux session: claude in a session of its own

A **session** here is a tmux session on the default server, named for the
work, whose window 0 is a plain shell with `claude` typed into it. You open
it; I take it from there, at the terminal or over Remote Control, with
`/resume`, `/rename` and the rest.

Two names, one work: the tmux session is `<name>` (`eye-breaks`), and the
claude in it is `<machine>/<name>` (`mbp/eye-breaks`), which is what Remote
Control and a phone notification show, across machines. `<machine>` is what
`~/.dotfiles/scripts/machine_name.sh` prints.

## Open a session

1. Settle the name and the folder from what I asked. The name is the work's
   (`eye-breaks`), the folder the one I named or the project's. When
   `tmux has-session -t =<name>` finds the name taken, tell me that session
   exists and stop there.
2. Create it detached, and type claude into its shell:

   ```bash
   tmux new-session -d -s <name> -c <folder>
   tmux send-keys -t =<name>:0 \
     "claude -n $(~/.dotfiles/scripts/machine_name.sh)/<name>" Enter
   ```

   `-n` is the one flag: `~/.claude/settings.json` starts every claude with
   Remote Control on, the agent view off and auto permission mode. Add
   `--dangerously-skip-permissions` when I asked for permissions bypassed in
   so many words, and only then.
3. Read the pane, `tmux capture-pane -p -t =<name>:0`, until it shows claude's
   empty prompt box. A folder claude has not opened before stops at a trust
   prompt instead, whose default is `No, exit`. Answer yes (`Down`, then
   `Enter`) for a folder I named in the request; for any other, ask me first:
   trusting a folder lets its own settings and hooks run on this machine.

Done when the pane shows the prompt box and you have told me the session's
name.

## Resume a conversation in one

1. Find the conversation's id and folder from the title I gave. Narrow by a
   word of it, then read each match's **current** title, which is the last
   one in its transcript: a transcript keeps the titles it had before, and
   one begun from another conversation keeps that one's too.

   ```bash
   for f in $(grep -l -i '"customTitle":"[^"]*<word>' ~/.claude/projects/*/*.jsonl); do
     printf '%s\t%s\t%s\n' \
       "$(grep -o '"customTitle":"[^"]*"' "$f" | tail -1 | cut -d'"' -f4)" \
       "$(basename "$f" .jsonl)" \
       "$(grep -m1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)"
   done
   ```

   Each line is title, id, folder. Keep the full `~/.claude/projects/` path
   in the glob: the folders under it start with `-`. With two candidates
   left, show me both and ask.
2. See that no claude has it open. An open one shows its title as a
   window's name (`tmux list-windows -a -F '#{session_name}: #{window_name}'`),
   and its id on a command line (`pgrep -fl <id>`) unless it was picked with
   `/resume` inside a claude already running. Found either way: name that
   session to me and stop there.
3. Open a session as above, in the conversation's folder, typing
   `claude --resume <id> -n <machine>/<name>`. `<name>`, the tmux session's
   too, is the title less a machine in front of it (`mbp/eye-breaks` and
   `eye-breaks` both give `eye-breaks`). The id, not the title:
   `--resume <title>` opens a picker when the title fits none or several,
   with nobody at the pane to answer it. The folder, because claude files
   conversations by the folder they ran in.

Done when the pane shows the end of that conversation above the prompt box.

## How a session is kept

- **A shell under claude.** Claude is a command typed into window 0, so a
  claude that quits or crashes leaves the shell at its prompt and the
  session up, windows and clients included, until claude is typed in again.
  Restarting a claude I named is typing it into that shell again.
- **One claude a session.** Further windows are mine: nvim, a shell.
- **Interactive.** The background agents (`claude --bg`, `claude agents`)
  are off on my machines.
- **One server.** Every session is on the default tmux server, so plain
  `tmux ...` reaches them all, and `tmux kill-server` would end them all.
  Close a session with `tmux kill-session -t =<name>`, and only the one I
  named.
- **`tmux-history`** is the server's history tracker
  (`scripts/tmux_history.py`): it takes no windows and no claude, and ends on
  its own.
