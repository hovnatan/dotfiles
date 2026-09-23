---
name: remote-run
description: "Remote machine work over ssh: sync code and inputs to the box, launch a job there, mirror its logs back. Load before the first ssh, rsync or scp that runs, benchmarks or trains anything on another machine."
---

# Remote runs

Three steps, in order: sync the box, launch the job, mirror its logs.

## Remote machines: sync one before you run anything on it

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

## Remote launches: own step, login shell, then read the first page

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

## Remote runs: keep a live local copy of the logs

When you start a long-running process on a remote machine, do not leave its
output only in the remote tmux pane or on remote disk. Mirror it to a file I
can open in VS Code on this VM: a background rsync loop (every ~30s, bounded
lifetime) from the remote output directory into a
`.logs/<timestamp>_remotework_<remote_name>_<work_description>/` directory
placed by the Observability rule in the global instructions (most specific
owning folder). Timestamp `YYYYMMDD_HHMMSS` in UTC. Tell me the local path
once the first refresh lands.
