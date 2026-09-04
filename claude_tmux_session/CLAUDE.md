# Claude tmux manager session

This directory is the working directory of the always-on "claude" tmux
session started at boot by claude-tmux.service (see
`../.config/systemd/user/claude-tmux.service` and
`../scripts/claude_tmux_run.sh`). That session runs Claude Code with
permissions bypassed and acts as the manager for the other Claude Code tmux
sessions on this machine.

## The setup

- All sessions live on a dedicated tmux server: `tmux -L claude ...`.
- Only the "claude" session is managed by systemd (recreated when it dies,
  killed by `systemctl --user stop claude-tmux`). Every other session is
  created on demand -- by you, when asked -- and survives service restarts
  and stops; nothing recreates one that exits.
- tmux session names are short (letters, digits, `-` and `_` only; the
  window title shows the first two characters). The Claude Code conversation
  behind a session is named `<hostname>-<session name>`, which is also its
  Remote Control name on claude.ai and its local peer name -- what
  `/list-agents` shows and what SendMessage addresses. `claude_tmux_run.sh`
  passes the name with `-n` on every launch, resumes included (a resume by
  id alone reverts the peer name to an auto-generated directory-based one).
  If a running session still shows an auto-generated peer name,
  `/rename <hostname>-<session name>` inside it fixes it live.
- A conversation is LABELED with its task once the task is clear:
  `/rename <hostname>-<session name>/<task>` inside the session (task: the
  session-name alphabet, letters, digits, `-` and `_`, e.g.
  `hov-8cpu-backend/asyncssh-advisory`), or `Ctrl+R` on its row in the
  `/resume` picker for a finished one. The label is what the picker, the
  prompt bar, the status line and claude.ai show; without it every
  conversation a name accumulates (one per `/clear`) reads the same. The
  peer name carries the label too, so address a labeled session by its
  full name (`ListAgents` shows it). Resumes keep the label; `/clear` would
  carry it into the fresh conversation, so the SessionStart hook below
  strips it there.
- The tmux session follows its conversation's name, label included:
  `backend/asyncssh-advisory` while that conversation runs, `backend`
  again after `/clear` (mechanism: Naming in `claude_tmux_run.sh`). tmux
  targets without `=` prefix-match, so `-t backend` reaches the session
  whatever its label; `=backend` matches only the unlabeled name.
- A session's prompt-bar color (`/color` inside Claude Code) survives
  `/clear`, which otherwise wipes it, and a task label does not leak past
  it: the SessionStart hook
  `~/.dotfiles/home/.config/tmux/session-clear.sh` types `/rename` back to
  the bare name and re-types the color the cleared conversation had.
  Resumes restore both on their own. Pick a color once per session with
  `/color`; nothing is configured anywhere.

## Bringing up a session

When asked to bring up / resume a session `<name>` (e.g. "backend"), run:

```
~/.dotfiles/scripts/claude_tmux_run.sh spawn <name>[/<task>] [dir]
```

It is idempotent. `spawn <name>` resumes the conversation most recently
talked in under `<hostname>-<name>`, labeled or not, in the directory that
conversation belongs to; `spawn <name>/<task>` pins the conversation
carrying that label (found with `history`, below) and refuses when the
`<name>` session is live with a different one -- switching means killing
work in flight, which is the user's call. When no such conversation exists
it starts a new one in `<dir>` -- required only in that case, so ask which
directory if it was not said. Spawned sessions run in auto permission mode
with Remote Control enabled. Append `--dangerous` only when the user
explicitly asks for a session with permissions bypassed -- never choose it
yourself.

One name can own SEVERAL conversations: a `/clear` inside a session keeps
the name while starting a fresh conversation beside the old one, and spawn
resumes whichever was talked in last (by last message, not file time: a
picker rename touches a file without anyone talking in it). A resumed id
that differs from the one resumed earlier that day is therefore normal
(`/clear`, or a new conversation started under a used name), not a bug --
but say so when it happens, since the user may have wanted the older
thread. To see them all, newest first, each with its label and opening
prompt:

```
~/.dotfiles/scripts/claude_tmux_run.sh history <name>
```

Resuming a specific older one is `spawn <name>/<task>` when it is labeled,
else `claude --resume <id> -n <its full title>` from that conversation's
own directory -- the same form `launch()` uses, and the `-n` matters: a
bare `--resume <id>` reverts the peer name, and a bare name drops the
label.

Before starting a NEW conversation, list what already exists:

```
~/.dotfiles/scripts/claude_tmux_run.sh conversations [pattern]
```

A session name says nothing about the directory behind it -- work on a
subfolder is usually done from a session rooted higher up, so the history
for `summit/project/bq-bench` lives in `bench`, rooted at
`~/deqart_workspace`. Spawning a name nobody used before always succeeds,
so a name that merely sounds right silently creates an empty second
conversation next to the one holding the work. If the listing shows a
plausible owner under another name, say so and offer it rather than
starting from nothing.

To stop a session: `tmux -L claude kill-session -t <name>` -- a bare name
prefix-matches its labeled form (`backend` finds `backend/asyncssh-advisory`);
`status` prints the exact names. `capture-pane` does NOT accept the
`=name` exact form ("can't find pane") -- resolve pane ids first with
`tmux -L claude list-panes -a -F '#{session_name} #{pane_id}'`.

## Reloading sessions after a Claude Code update

There is no restart subcommand: kill the session, then spawn it again. The
resumed conversation id is unchanged by this (a resume writes into a NEW
transcript file, so the id from `spawn` can differ from the one you saw
before -- see above).

Reload only IDLE sessions. A reload buys a fresh binary; it is never worth
killing work in flight, and "reload all sessions" does not authorise that.
Capture every target's pane first and leave a session alone when it shows:

- a turn in progress -- a spinner with an elapsed timer at the bottom.
  Capture twice a few seconds apart: an advancing timer means it is
  working, not stuck, however long it has been going.
- a background shell, watcher or Monitor the harness still TRACKS -- killing
  one leaves no completion record, so the resumed session only learns the
  command "may have been running when the process exited" and has to redo it.
  Tracked means a live CHILD of the session's `claude` pid. A process merely
  carrying that session's `CLAUDE_PID`/`TMUX_PANE` env but reparented to
  systemd was detached on purpose (`setsid nohup ... > log`): it survives the
  kill untouched and nothing was tracking it, so it is NOT a reason to skip.
  Grep the session's transcript for how it was launched before believing an
  env stamp.

Reload the idle ones, then name the ones you skipped and why, and offer to
come back for them once they go quiet.

Which build each session actually runs:

```
tmux -L claude list-panes -a -F '#{session_name} #{pane_pid}' |
  while read s p; do
    for q in $p $(pgrep -P $p) $(pgrep -P $p | xargs -r -I{} pgrep -P {}); do
      e=$(readlink /proc/$q/exe); case "$e" in */versions/*) echo "$s ${e##*/}"; break;; esac
    done
  done
```

Compare against `claude --version` (the `~/.local/bin/claude` symlink). Do
not judge from the pane: the version banner is only drawn for a FRESH
conversation, and a resumed one shows the `Restart to update` notice
instead.

- The installer can flip that symlink mid-reload, so sessions spawned
  seconds apart land on different builds. Check versions after reloading a
  batch and restart the stragglers.
- A kill discards text the user typed into the prompt but never sent -- but
  the input box ALSO renders Claude Code's suggested-action hint, which
  echoes the recap's next step ("commit this" under a recap ending "next is
  committing them"). `capture-pane -p` strips the styling that separates the
  two, so a line in the box is not proof of pending input. Quote it back and
  ask; never skip a reload over it. (`-e` keeps the SGR codes to compare.)
- A reload resets per-process runtime state even though the conversation is
  intact: effort drops to the default (`max` -> `xhigh`) and the session's
  cwd returns to its launch directory. Report both so the user can restore
  them.
- This manager session cannot reload itself. Tell the user to run
  `systemctl --user restart claude-tmux`; systemd recreates the session and
  resumes this conversation.

Never run `claude_tmux_run.sh` with no arguments -- that is the systemd
entrypoint, which blocks forever in a watch loop -- and never `pkill -f` on
its name, because the pattern matches the service's own process. Read the
script when you need its usage. (Killing the service is survivable: its
ExecStop only kills the manager session when MAINPID is still set, so a
signalled service auto-restarts without taking the session down.)

## Daily work log

The user may ask, at the end of a day, to add that day's work -- and a
`Next` section of the following day's tasks -- to a Google Doc work log.
Invoke the `work-log` skill, which carries the whole routine; the document
ids and the other identifying details it needs are in
`~/.config/claude-worklog/`, symlinked out of the private companion repo at
`~/.dotfiles-private`. If that directory is missing, the repo is not cloned
-- ask the user for it.

## Azure

This file is public, so VM and resource-group names stay out of it; look
them up: `az vm list --query "[?name=='<vm>'].resourceGroup" -o tsv` (fast
without `-d`). Deallocating is then `az vm deallocate --no-wait -g <group>
-n <vm>`; run it unpiped, or the exit status you check belongs to the last
command of the pipe.

`az vm list -d` is the power-state query, and `-d` makes it fetch an
instance view per VM: it needs **five minutes or more**, well past the
default command timeout, after which it is still running in the background
rather than finished. Give it an explicit long timeout and wait. A call that
timed out tells you nothing about any VM's state -- do not report from it.

## Fleet policy: docker on cgroupfs, apt upgrades at boot only

Every hov-fleet VM -- new and existing, CPU and GPU alike -- runs docker on
the cgroupfs cgroup driver and takes unattended upgrades once at boot
instead of on the daily timer. On a fresh or rebuilt box, apply both before
real work runs on it; on an existing box found non-compliant, apply at the
next idle moment.

Why. Docker's default systemd cgroup driver has a revocation bug on GPU
boxes: the nvidia-container-toolkit's hook grants /dev/nvidia* access
outside the runc spec, so systemd does not know the container holds it, and
anything that makes systemd re-apply device policy -- a
`systemctl daemon-reload` (apt upgrades trigger these), a guest-agent
self-update, unit edits -- silently kills CUDA inside RUNNING containers
(`cudaErrorNoDevice` / NVML "Unknown Error") while host nvidia-smi stays
healthy. This voided real benchmark samples three times in Aug 2026.
CPU boxes are not exposed to that bug, but carry the policy anyway for
uniformity, and because mid-run unattended upgrades contend with
benchmarks. Boot-time upgrades keep boxes patched when no workload exists
yet.

How:
- `"exec-opts": ["native.cgroupdriver=cgroupfs"]` merged into
  /etc/docker/daemon.json, then restart docker (idle box only). Verify
  with `docker info --format '{{.CgroupDriver}}'`.
- `apt-daily-upgrade.timer` disabled; a oneshot
  /etc/systemd/system/apt-upgrade-on-boot.service (WantedBy
  multi-user.target, Before=docker.service, TimeoutStartSec=15min, runs
  `systemctl start apt-daily-upgrade.service`) enabled instead, plus a
  docker.service drop-in (Wants= + After= that oneshot) so no container
  can exist while the boot upgrade's daemon-reload fires. apt-daily.timer
  (the download half) stays enabled.
- WALinuxAgent stays at its DEFAULT self-update behavior (goal-state
  driven, Azure's schedule): disabling it was tried 2026-08-24 and
  reverted -- the agent package ships from -updates, which
  unattended-upgrades' security-only origins never install, so "boot-time
  agent updates" would really mean "no agent updates". Its occasional
  self-respawn is harmless once docker is on cgroupfs.
- Until a box is switched: never `systemctl daemon-reload`, install
  packages, or edit/enable units while a GPU container is mid-run there --
  registering a new unit needs a daemon-reload, which is exactly the
  trigger.

## GPU boxes: the MIG-after-deallocate trap

A deallocate/start cycle can land a GPU VM on a physical A100 with MIG
mode ENABLED -- the mode lives in the GPU hardware, not the VM image. The
symptom is nasty: nvidia-smi works everywhere (host and containers,
driver loaded, devices injected) but EVERY CUDA init -- host cupy, agent
and grade containers -- fails with cudaErrorNoDevice, because MIG-on with
zero instances exposes no CUDA devices. This silently invalidated two
full benchmark arms before it was caught.

After every VM start on a GPU box:
- `nvidia-smi --query-gpu=mig.mode.current --format=csv,noheader`; if
  Enabled: `sudo nvidia-smi -mig 0 && sudo nvidia-smi --gpu-reset`
  (works in place on passthrough boxes, no reboot).
- Then smoke-test REAL CUDA (`python -c "import cupy;
  cupy.arange(5).sum()"` or a ctypes cuInit(0)) -- never trust nvidia-smi
  alone.
- Fleet GPU boxes carry a boot-time guard for this
  (gpu-mig-guard.service: auto-disables MIG, gpu-resets, verifies
  cuInit(0), logs to journal); install it on any new GPU box, and treat
  any surprising all-fail GPU run as "re-check the canonical/reference
  first", not as a result.

Related boot-time GPU setting, required on ALL GPU hov VMs: NVML
**accounting mode** (`sudo nvidia-smi -am 1`; check with
`nvidia-smi --query-gpu=accounting.mode --format=csv,noheader`). It makes
the driver track each CUDA process's peak device memory exactly (no
sampling, no perf cost, queryable after the process exits). Like MIG mode
it does NOT survive a deallocate/start cycle, so the gpu-mig-guard boot
script re-enables it; on a new GPU box enable it along with the guard.

## Rules

- Do not kill or restart sessions you were not asked to touch, and do not
  kill the tmux server (it hosts all of them).
- Permissions bypass is reserved for this manager session and for spawns
  the user explicitly requested with it (`--dangerous`).
- Never use background agents in this flow. Every session is an interactive
  Claude Code process in a tmux window, spawned by `claude_tmux_run.sh`.
  Do not run `claude --bg`, do not dispatch work from the `claude agents`
  view, and do not leave a daemon running: a background agent holds the
  conversation's transcript open, so the next spawn of that name is refused
  ("already open in another claude process"), and the daemon respawns a
  worker you kill with a signal, under a new pid. Note that merely opening
  `claude agents` starts a transient daemon -- if you open it (it is the
  only way to stop one background agent without touching the others: select
  the row, `ctrl+x`), run `claude daemon stop --any` afterwards.
  `claude daemon stop --any` terminates every background session and the
  supervisor; interactive tmux sessions are unaffected.
- Sessions are launched with `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`, which
  turns off `claude agents`, `--bg`, `/background` and the supervisor for
  them -- including the left arrow that opens the agent strip, which
  otherwise starts a daemon and leaves a background session behind on every
  press. The variable is inherited by anything a session runs, and under it
  `claude agents --json` prints a refusal and exits 0, so the spawn guard
  calls it via `env -u CLAUDE_CODE_DISABLE_AGENT_VIEW` -- keep that wrapper,
  or the guard goes blind and double-opens a conversation.
- A turn can resume long after the previous one, on a machine that rebooted
  in between: the VM gets deallocated and started again, and systemd
  recreates this session. Before explaining current state by something you
  did earlier, re-establish the clock -- `date`, `uptime -s`,
  `journalctl --list-boots`. A VM running now is not evidence that an
  earlier deallocate failed.
