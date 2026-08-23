# Observability: report progress as it happens, not only at the end

Write code and experiments so I can watch them work, at whatever cadence
suits the loop - per step when steps are slow, every N steps or few seconds
when they are fast - stamping each line with a time and an index or key so it
means something on its own. Mind buffering only where it bites: stdout goes
block-buffered once piped or redirected to a file, while a terminal, stderr
and `logging` stay line-buffered on their own. Flush at the emit site with
`print(..., flush=True)` and line-buffered result files; save
PYTHONUNBUFFERED=1 for programs you cannot edit (`stdbuf` has no effect on
Python).

Persist as you go, not only to the terminal. Append results as they are
produced, and write anything expensive to recompute to a temp file in the
same directory and rename it into place, so a kill mid-write cannot corrupt
it. A run killed at 80% should leave 80% of its output on disk and be
inspectable mid-flight. Unless the project has its own layout, put it under
`.logs/<timestamp>_<work_description>/` (UTC `YYYYMMDD_HHMMSS`), placed by
the same rule as "Remote runs" below, whose naming wins when the work is
remote. `.logs` is gitignored on this machine only - add it to the project's
.gitignore anywhere else. Tell me the path when the run starts (for a remote
mirror, once the first refresh lands).

Keep it proportionate: where reporting genuinely costs real performance,
lengthen the interval rather than dropping it, and say when you make that
trade. The same goes for your own long tasks - surface a finding when you
have it instead of holding everything for the final report, unless the task's
output contract is a single structured payload.

# Remote runs: keep a live local copy of the logs

When you start a long-running process on a remote machine, do not leave its
output only in the remote tmux pane or on remote disk. Mirror it to a file I
can open in VS Code on this VM: a background rsync loop (every ~30s, bounded
lifetime) from the remote output directory into a
`.logs/<timestamp>_remotework_<remote_name>_<work_description>/` directory
placed in the most specific folder the work belongs to - the experiment's
own package/environment folder, not the repo root. Fall back to the repo root
`.logs/` only when no subfolder clearly owns the
work. Timestamp `YYYYMMDD_HHMMSS` in UTC. Tell me the local path once the first refresh lands.

# Memory updates: consider promoting to repo-tracked docs

When you write to the memory directory, decide in the same turn (and say)
whether the fact belongs in a git-tracked layer instead: project skills for
pipeline lessons, repo CLAUDE.md/AGENTS.md for conventions. Personal
preferences and machine/account specifics stay in memory only.

# Plain ASCII

Default to plain ASCII everywhere - code, comments, commit messages, prose -
unless non-ASCII is genuinely required. In prose, fancy typography (em dashes,
smart quotes) reads as an LLM tell; in code, lookalike Unicode trips ruff
RUF001-003. Use `-`/`--`, straight quotes, `...`, `->`.

# Slack: self-DM only

When sending through the Slack MCP tools, never send directly to the real
recipient: direct sends carry an unsuppressible "Sent using @Claude" footer,
and slack_send_message_draft drops markdown links (only the label text
survives). Instead post the message to my self-DM (my own user id as
channel_id) and give me the message link; I copy-paste from there.

# Ntfy: how to notify my phone

When I ask to be notified on my phone / via ntfy, POST to the ntfy.sh topic
named in `~/.config/claude-ntfy/topic` (machine-local, deliberately not
committed -- a topic name is a read capability; this file is public). If
the file is missing on a machine, ask me for the topic rather than
inventing one.

    curl -sf --max-time 10 -H "Title: <short title>" -d "<message>" \
      "https://ntfy.sh/$(cat ~/.config/claude-ntfy/topic)"

From Python, stdlib urllib does the same (POST body = message; Title/Tags
as headers) -- no dependencies needed. The Stop-hook pipeline
(`~/.dotfiles/home/.claude/ntfy-stop.sh`) reads the same topic file, so one
subscription covers both.
