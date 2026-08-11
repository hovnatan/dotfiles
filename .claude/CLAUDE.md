# Python

When working with Python, invoke the relevant /astral:<skill> for uv, ty, and ruff.
For standalone scripts, prefer PEP 723 inline script metadata (`# /// script`)
over requirements files or project scaffolding, so they run with `uv run script.py`.

# Git

Never stage (`git add`), commit, or push unless I explicitly ask. Never force
push unless I explicitly ask for a force push - a regular push request does not
count. A PreToolUse hook (~/.dotfiles/.claude/git-guard.sh) prompts on every
commit/push; that is expected, do not work around it.

Never move a pinned git submodule off the commit its superproject records
unless I explicitly ask. That means no picking a different commit from inside
a submodule (`git -C <sub> checkout/pull`) and no advancing pins from the
superproject (`git submodule update --remote`, `git submodule foreach git
pull`) - my submodules pin tracked branches, so those commands drift silently.

"Update the sources" for a repo with submodules means updating the
superproject and then restoring its pins with `git submodule update --init
--recursive`; without `--init`, an uninitialized submodule is skipped with no
output and left empty. Verify with `git submodule status` (leading `-` =
uninitialized, `+` = wrong commit), not `git -C <sub> rev-parse HEAD`, which
returns the superproject's HEAD when the submodule directory is empty. If a
submodule has local edits, tell me rather than forcing past them (`--force`
discards them). Pins exist so results stay reproducible against a known
dependency version.

# Remote runs: keep a live local copy of the logs

When you start a long-running process on a remote machine, do not leave its
output only in the remote tmux pane or on remote disk. Mirror it to a file I
can open in VS Code on this VM: a background rsync loop (every ~30s, bounded
lifetime) from the remote output directory into
`.logs/<timestamp>_remotework_<remote_name>_<work_description>/` inside the
repo the work belongs to, e.g.
`.logs/20260811_143000_remotework_hov-128cpu_spsa_vs_autodiff/` (timestamp
`YYYYMMDD_HHMMSS` in UTC, as in the config filenames). Tell me the local path
once the first refresh lands.

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

# Slack: I paste raw markup

My Slack client has "Format messages with markup" enabled: draft Slack-bound
messages as raw mrkdwn I can paste as-is. Slack mrkdwn is not GitHub markdown
(no headers, `<url|text>` links, single `*` = bold). Tabular data goes in a
``` fence with space-aligned columns, no leading indentation.

When sending through the Slack MCP tools, never send directly to the real
recipient: direct sends carry an unsuppressible "Sent using @Claude" footer,
and slack_send_message_draft drops markdown links (only the label text
survives). Instead post the message to my self-DM (my own user id as
channel_id) and give me the message link; I copy-paste from there.
