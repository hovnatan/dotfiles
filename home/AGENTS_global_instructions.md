# Technical decisions: weigh the long term, not the build cost

When choosing between approaches, give little weight to how long something
takes to build. Prefer quality, simplicity, robustness, scalability and
long-term maintainability. Where the cheap option is materially worse, say
so plainly and let me take the trade knowingly rather than quietly picking
whichever is fastest to write.

# One-off work: take the direct path

For one-off or infrequent operational work, start with the simplest direct
end-to-end path. Do not build wrappers, control planes, policy layers,
custom verifiers, or automation around it unless the direct path hits a
concrete blocker, or the need repeats often enough to pay for the machinery.
The scaffolding usually costs more than the task and outlives its purpose.

# Bug fixes: reproduce end to end first

Before fixing a bug, reproduce it end to end, as close to how a user hits it
as you can get. A fix written against a guess at the cause tends to solve a
different problem than the one reported, and looks like a success until it
does not. Once you have a reproduction, keep it as the check that the fix
actually works.

# Slack links: read the conversation around them

When a prompt includes a link to a Slack message, read beyond that one message:
the thread it belongs to (parent and replies) and the channel messages just before
and after it, enough to know what it answers and what came of it. A linked message
alone is often a reply whose question sits above it, or a claim corrected below it.

# Lint, test failures, and flakiness: fix what you find

Hold engineering hygiene to the same standard as the task at hand. If you hit
a lint error, a failing test, or a flaky one, fix it along the way even when
it predates your change and is unrelated to it, and tell me what you fixed.
If a fix is too large to fold in, say so and leave a note - do not step
around it silently.

# Cruft: tell me when you see it

When the work takes you past something that costs more than it gives, say
so: machinery bigger than the job it does, a mechanism whose benefit is
doubtful, two things doing one job, a design that fights the tool it sits
on, a leftover from an approach since dropped, a rule or script nothing
uses. One line each at the end of your reply: what it is, what it costs, and
whether it can simply go or what simpler thing would replace it. Only what
you would cut or simplify if it were yours, not matters of taste. This holds
for what you built earlier in the session as much as for what you found.
Report what you came across; do not go hunting for it, and do not remove it
unless I ask.

# Code comments: few, and only the why

Leave code uncommented unless a reader would get it wrong without one: a
constraint the code cannot show, a workaround and what it works around. No
restating the code and no history of how it got there - that is the commit
message, and a decision worth keeping is an ADR. Do not match a file's
heavier commenting when you edit it; fix or delete a comment your change
makes untrue.

# Layer boundaries: no new punched holes

Where a codebase has layers, route new calls through the layer directly
below; do not reach past it to a database query, raw socket, or hardware
detail even when that is fewer lines. When building something durable,
wrap low-level mechanics in a small API so callers speak domain concepts,
not implementation details. Where hole-punching is the codebase's idiom,
follow it and say so.

# Git worktrees: only when I ask

Work in the checkout you were started in: edit, test, commit and push from it,
so the changes are where I look for them. Create a git worktree (by hand,
`EnterWorktree`, or a subagent's worktree isolation) only when I ask for one.
When another session works in the same checkout, stage and commit only your
own files by path and leave its uncommitted changes alone.

# Observability: report progress as it happens, not only at the end

Write code and experiments so I can watch them work, at whatever cadence
suits the loop - per step when steps are slow, every N steps or few seconds
when they are fast - stamping each line with a time and an index or key so it
means something on its own. Output piped or redirected to a file is
block-buffered, so flush at the emit site (`print(..., flush=True)`,
line-buffered result files) and the lines land as they are written.

Persist as you go, not only to the terminal. Append results as they are
produced, and write anything expensive to recompute to a temp file in the
same directory and rename it into place, so a kill mid-write cannot corrupt
it. A run killed at 80% should leave 80% of its output on disk and be
inspectable mid-flight. Unless the project has its own layout, put it under
`.logs/<timestamp>_<work_description>/` (UTC `YYYYMMDD_HHMMSS`) in the most
specific folder the work belongs to - the experiment's own
package/environment folder, not the repo root; fall back to the repo root
`.logs/` only when no subfolder clearly owns the work. `.logs` is gitignored
on this machine only - add it to the project's .gitignore anywhere else. Tell
me the path when the run starts.

Keep it proportionate: where reporting genuinely costs real performance,
lengthen the interval rather than dropping it, and say when you make that
trade. The same goes for your own long tasks - surface a finding when you
have it instead of holding everything for the final report, unless the task's
output contract is a single structured payload.

# Results: leave a handoff document next to the artifacts

When a task produces results someone will later read, compare against, or
reproduce - an experiment, a sweep, a benchmark, a migration - write or extend
a README next to the artifacts as part of finishing the task, not only when I
ask. Put it in the most specific folder that owns the work, and extend the
existing document when the work continues an earlier experiment rather than
starting a rival one; splitting one experiment's record across two places is
worse than a long file.

What earns its place: the headline numbers in a table (per-run and aggregate,
with the spread, not just the winner); what was held fixed and what varied
(seeds, splits, thresholds, hardware); the takeaway a reader should quote,
and the one they should not; where the artifacts live (DVC path, bucket, run
dirs) and the revision that produced them; the exact commands to reproduce;
and the gotchas that cost me time - stale config fields, CLI flags whose
defaults surprised us, wall-clock per stage. Prefer plain numbers over
adjectives, and say which result is noise.

# File paths: give them in full

When you point me at a file or folder, write its full path from `~`
(`~/work/repo/.logs/<run>/README.md`, never `/home/me/...` or `/Users/me/...`),
so I can open it or `cd` to it from any terminal without knowing your working
directory. This matters most for artifacts outside the tracked tree - `.logs/`
runs, temp files, remote mirrors - which I cannot find by searching the repo. A
repo-relative `path:line` is fine for citing source code inside the repo we
are both working in.

Claude Code folds a reply's prose at 90 columns, and the fold is a real
newline, so a path cut by it comes out broken when copied. Put each path I am
meant to open or `cd` to on its own line, flush left with no list indent, so no
words around it can push it into the fold. A path longer than about 85
characters goes as its folder on one line and the file names under it.

# Markdown: lint what you write

Lint every markdown file you create or edit with markdownlint-cli2 before
calling it done, and get it to 0 issues (it is in my Nix package set; on a
machine without it, `npx markdownlint-cli2`). Where the project has its own
config (`.markdownlint-cli2.*` or `.markdownlint.*`), run it the way the
project does - its rules win, and if it lints a whole set of files the whole
set must pass. Where it has none, pass mine, which holds prose and lists to
90 characters per line:

```bash
markdownlint-cli2 --config ~/.config/markdownlint/.markdownlint.yaml <files>
```

The findings worth the most are text that renders wrong: a `|` inside a table
cell (write `\|`), `*` or `_` in math read as emphasis, a line starting with
`+` read as a bullet, a `<placeholder>` outside a code span read as HTML.
`--fix` is safe for spacing but rewrites exactly those cases wrongly, so fix
them by hand and read its diff before keeping it. Keep table cells to a
phrase: when a cell needs a sentence, write a list or a section instead.

Lint the files you touched. Do not reflow or re-style someone else's file to
satisfy the linter unless I ask or the project's config already covers it.

# Password prompts: my own terminal, not `!`

`!` runs without a tty, so sudo and other password prompts fail there.
Hand those commands to me to run in my own terminal window; keep `!` for
interactive logins that open a browser or read no password.

# Commands for me to run: a short line, the rest in a file

Claude Code wraps long lines itself when it draws a reply, so a command I
copy from the screen carries hard newlines; a break inside quotes or after
`>` changes what it does (`cat >` lost its file name, 2026-11-13). When
you hand me a command to run (with `!` or in my own terminal) that would
not fit on one screen line, write it to a script under `/tmp` with a short
name, check it (`bash -n`, shellcheck), show what it does, and give me
`! bash /tmp/<name>.sh`. Keep the path short too: a long one wraps as well.

# Failures: loud, not silent

In everything code-related, an unexpected state should fail where it
happens, with a message that names what went wrong and how to fix it. This
covers the environment as much as the logic: a missing dependency,
credential, service, config key or schema column is a finding, not
something to route around. Do not paper over it: no skip on a missing
import, no broad `except` that logs and continues, no fallback to a
degraded path, no default that stands in for data that should have been
there, no `.get()` where the key is required, no clamping or coercing a
value that is out of range. Each of these turns a bug into a wrong result
that surfaces far from its cause. Raise, assert the invariant, or let the
exception propagate. Examples: a test importing a package should fail
collection when the package is absent, not `pytest.importorskip` it,
because the missing package is the finding; a parser meeting an unknown
field should raise, not drop it. Skips, fallbacks and defaults are for
conditions that are optional by design (no GPU on this machine, a feature
flag off, an optional config key with a documented default), not for states
that should have been correct. When you think swallowing an error is right
anyway, say why and let me decide.
