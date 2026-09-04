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

# Lint, test failures, and flakiness: fix what you find

Hold engineering hygiene to the same standard as the task at hand. If you hit
a lint error, a failing test, or a flaky one, fix it along the way even when
it predates your change and is unrelated to it, and tell me what you fixed.
If a fix is too large to fold in, say so and leave a note - do not step
around it silently.

# Code comments: explain the why, and draw the system

In code you write or reshape, comment at the block level: separate logical
blocks with blank lines, and give a block a short note on what it does and
why - the intent or constraint the code cannot show, never a restatement
of the next line. A concrete example (input -> output, an edge case) beats
an abstract description. When a module has several interacting parts, put
an ASCII diagram in a comment or docstring - data flow, state machine -
so the structure is visible without reading every function.

# Layer boundaries: no new punched holes

Where a codebase has layers, route new calls through the layer directly
below; do not reach past it to a database query, raw socket, or hardware
detail even when that is fewer lines. When building something durable,
wrap low-level mechanics in a small API so callers speak domain concepts,
not implementation details. Where hole-punching is the codebase's idiom,
follow it and say so.

# Subagent swarms: ask before spawning one

Before using dynamic workflows, ultracode, or any harness feature that
immediately spawns a large swarm of subagents, explain the tradeoffs - cost,
wall-clock time, and what it buys over doing the work directly - and wait for
my explicit approval.

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

# Remote machines: sync one before you run anything on it

Before doing work on a remote machine, bring it up to date - a box is
usually days behind, or ahead by someone else's changes, and a run on it
silently benchmarks stale code that looks like a real result. Code moves
over git - `git fetch` plus checkout/pull in every repo involved - so only
tracked files travel. When the remote cannot reach the origin itself (no
deploy key, an expired token, no route out) or is not a checkout at all,
rsync the tracked set plus `.git`:

    { git ls-files -z; printf '.git\0'; } |
      rsync -azr --files-from=- --from0 ./ remote:path/

`--files-from` cancels the recursion `-a` implies, so `-r` is what actually
carries `.git`. `.git` is part of that set, never a size-gated extra:
without it the box cannot say which revision it holds and anything that
reads HEAD there breaks.

Then rsync what git does not carry and the work reads - an uncommitted
patch, a config, the input - at the granularity the job consumes: a
mounted directory, an imported package, a build context, a dataset root
travel whole, not the files you believe it touches, since a hand-picked
subset changes what the run can see and its numbers stop matching a run
here.

Never push what the remote can rebuild or refetch: `.venv`, `.tox`,
`node_modules`, `__pycache__`, lint and build caches, DVC-managed data and
environment dirs, and anything it can pull itself (`dvc pull`, a bucket
copy, a model download). For everything else gate on time, not bytes: size
it with `rsync -n --info=stats2`, divide by the link's rate (a datacenter
peer moved 3.5 GB of `.git` in 36 s), and past a few minutes ask me before
the run starts. The gate decides whether I hear about it first, never what
travels.

The toolchain is part of the sync: match `--version` for the tools the run
invokes - interpreter, package manager, container runtime, accelerator
stack - and give the box the user config `~/.dotfiles` links under
`~/.config`; without it every tool runs on different defaults (uv without
`exclude-newer` rewrote a committed lockfile on every `uv run`). A file the
remote regenerates is drift: fix the cause there, never sync the rewrite
back.

Then prove the sync with git on both sides (rsync's own exit already
covers what it sent; do not re-run it with `-n`): `git rev-parse HEAD; git
status --porcelain | wc -l` here and there, reported as
`<repo> @ <rev> (<n> dirty) == remote @ <rev> (<n> dirty)` and stamped into
the run's output directory at launch unless the harness records it. If the
sync cannot be clean - uncommitted or regenerated files on the remote, a
diverged branch, a conflict - stop and tell me rather than forcing or
stashing it away; those changes are often why the box is in that state.

# Remote launches: own step, login shell, then read the first page

Start the job as its own step, never chained onto the transfer with `&&`:
when the pair times out you cannot tell which half ran. A non-interactive
ssh gets no login PATH, so run it through a login shell, detach it with
every fd redirected, and prove it alive in the same call:

    timeout 30 ssh remote bash -l <<'EOF'
    cd <dir> && setsid nohup <cmd> > <log> 2>&1 < /dev/null &
    sleep 1; kill -0 $! && echo "launched $!"
    EOF

`launched <pid>` is the confirmation. ssh should return at once; `timeout`
is a guard, and exit 124 alone says nothing about the job (ssh has lingered
even with every fd redirected) - look again. Then read the first page of
the run's log before walking away: a line saying it ignored, regenerated or
fell back to something is the sync failing late - kill it at minute one,
not hour three.

# Remote runs: keep a live local copy of the logs

When you start a long-running process on a remote machine, do not leave its
output only in the remote tmux pane or on remote disk. Mirror it to a file I
can open in VS Code on this VM: a background rsync loop (every ~30s, bounded
lifetime) from the remote output directory into a
`.logs/<timestamp>_remotework_<remote_name>_<work_description>/` directory
placed in the most specific folder the work belongs to - the experiment's
own package/environment folder, not the repo root. Fall back to the repo
root `.logs/` only when no subfolder clearly owns the work. Timestamp
`YYYYMMDD_HHMMSS` in UTC. Tell me the local path once the first refresh
lands.

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
