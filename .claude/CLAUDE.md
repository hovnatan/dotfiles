# Python guidelines

When working with Python, invoke the relevant /astral:<skill> for uv, ty, and ruff to ensure best practices are followed.

# Never stage, commit, or push unless explicitly asked

Do NOT run `git add` (or otherwise stage files), `git commit`, or `git push`
unless I explicitly ask for it. Make changes to the working tree as needed,
but leave staging and committing to me unless I say so.
NEVER force push (`git push --force` or `--force-with-lease`) unless I
explicitly ask for a force push - asking for a regular push does not count.

These rules are also enforced by a PreToolUse hook
(~/.dotfiles/.claude/git-guard.sh): every git commit and push - force pushes
included - triggers a permission prompt so I approve each one explicitly.
If the hook prompts, that is expected; do NOT try to work around it (e.g.
`sh -c`, editing settings.json, disabling hooks).

# Memory updates: consider promoting to repo-tracked docs

Whenever you create or update a file in the Claude memory directory
(~/.claude/projects/*/memory/), explicitly consider in the same turn whether
the fact belongs in the git-tracked layer instead of (or in addition to)
memory, and say what you decided:

- project skills (e.g. `sdk/.claude/skills/...`) for operational pipeline
  knowledge and lessons from runs;
- repo CLAUDE.md / AGENTS.md for repo-wide conventions and procedures.

Memory is machine-local; repo files reach every VM and teammate via git.
Do NOT promote personal preferences or machine/account specifics (VM names,
SSH details, my workflow choices) into team-shared repo files - those stay
in memory.

# Use plain ASCII, avoid ambiguous Unicode characters

Default to plain ASCII everywhere -- code, strings, comments, identifiers, commit messages, and prose/Markdown -- unless a non-ASCII character is genuinely required (e.g. a proper noun, a real math symbol, an existing API). Two reasons:
- In prose, fancy typography (especially the em dash) reads as an LLM tell. Prefer plain `-` / `--`.
- In code, many Unicode characters look like ASCII but are not, and linters (e.g. ruff RUF001/RUF002/RUF003) reject them: "String contains ambiguous `×` (MULTIPLICATION SIGN). Did you mean `x`?".

Common offenders and their ASCII replacements:
- `–` `—` (en/em dash) -> `-` or `--`
- `“` `”` `‘` `’` (smart quotes) -> `"` `'`
- `…` (ellipsis) -> `...`
- `×` (multiplication sign) -> `x` or `*`
- `→` (arrow) -> `->`
- `·` (middle dot) -> `.` or `*`
- non-breaking space (U+00A0) -> regular space

# Slack: I paste raw markup, not rich formatting

My Slack client has "Format messages with markup" enabled (no WYSIWYG editor).
When drafting Slack-bound messages for me, give raw mrkdwn I can paste as-is:
- *bold*, _italic_, `inline code`, and literal ``` fences typed inline (they
  become code blocks on send); bullets as `*` or `-` lines.
- Slack has no tables: put tabular data inside a ``` block with space-aligned
  columns and no leading indentation (outside a block Slack's proportional
  font destroys alignment).
- Slack mrkdwn is not GitHub markdown: no headers, no [text](url) links
  (use <url|text> instead), and single *asterisks* mean bold, not italic.
