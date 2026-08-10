# Python

When working with Python, invoke the relevant /astral:<skill> for uv, ty, and ruff.
For standalone scripts, prefer PEP 723 inline script metadata (`# /// script`)
over requirements files or project scaffolding, so they run with `uv run script.py`.

# Git

Never stage (`git add`), commit, or push unless I explicitly ask. Never force
push unless I explicitly ask for a force push - a regular push request does not
count. A PreToolUse hook (~/.dotfiles/.claude/git-guard.sh) prompts on every
commit/push; that is expected, do not work around it.

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
