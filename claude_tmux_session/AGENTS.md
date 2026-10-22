# Claude Code tmux manager session

This directory is the working directory of the always-on "manager" tmux
session started at boot by claude-tmux.service (see
`../home/.config/systemd/user/claude-tmux.service` and
`../scripts/claude_tmux_run.sh`). That session runs Claude Code with
permissions bypassed and acts as the manager for the other Claude Code tmux
sessions on this machine.

## The setup

- All sessions live on a dedicated tmux server: `tmux -L claude ...`.
- Only the "manager" session is managed by systemd (recreated when it dies,
  killed by `systemctl --user stop claude-tmux`). Every other session is
  created on demand -- by you, when asked -- and survives service restarts
  and stops; nothing recreates one that exits.
- tmux session names are short (letters, digits, `-` and `_` only; the
  window title shows the first two characters). The Claude Code conversation
  behind a session is named `<hostname>/<session name>`. A session has ONE
  name: the prompt bar, `/list-agents` (what SendMessage addresses), the
  `/resume` picker and claude.ai all show it, and `/rename` from any of
  them changes it everywhere; claude.ai lists every machine's sessions,
  hence the hostname. `claude_tmux_run.sh` passes the name with `-n` on
  every launch, resumes included (a resume by id alone reverts the peer
  name to an auto-generated directory-based one). If a running session
  still shows an auto-generated peer name,
  `/rename <hostname>/<session name>` inside it fixes it live.
- Until 2026-10-22 the form was `<hostname>-<session name>`, and older
  conversations and running sessions still carry it. Every command below
  still finds them, and the next `load` or `restart` of one renames it to
  the `/` form. Address a running one by the name `ListAgents` shows.
- A conversation is LABELED with its task once the task is clear:
  `/label <task>` inside the session, or `prefix L` from tmux, either of
  which types the full `/rename <hostname>/<session name>/<task>` (task: the
  session-name alphabet, letters, digits, `-` and `_`, e.g.
  `vm/backend/fix-login`), or `Ctrl+R` on its row in the
  `/resume` picker for a finished one. The label is what the picker, the
  prompt bar, the status line and claude.ai show; without it every
  conversation a name accumulates (one per `/clear`) reads the same. The
  peer name carries the label too, so address a labeled session by its
  full name (`ListAgents` shows it). Resumes keep the label, and so does
  `/clear`: the fresh conversation inherits it, so relabel it (or
  `/rename` back to the bare name) once its own task is clear. Until then
  two conversations carry one label, and `load <name>/<task>` refuses.
- The tmux session follows its conversation's name, label included:
  `backend/fix-login` while that conversation runs, `backend`
  again once it is renamed to the bare name (mechanism: Naming in
  `claude_tmux_run.sh`). tmux
  targets without `=` prefix-match, so `-t backend` reaches the session
  whatever its label; `=backend` matches only the unlabeled name.
- A prompt-bar color (`/color`) does not survive `/clear`; only a resume
  brings it back (Claude Code does that itself).
- What a session starts ends with it. Each pane runs in a systemd scope
  of its own, and when a session closes, however it closes, the scopes of
  its panes are stopped (`home/.config/tmux/reap-panes.sh`, logged in the
  tmux hooks' log): a `setsid nohup` job, a proxy, a watcher started from a
  session does not survive it. Nor does it survive a `restart` (or
  `prefix C-r`), which stops the old claude's scope once the new one runs.
  A job meant to outlive its session runs as a unit of its own:
  `systemd-run --user --unit=<name> <command>` (then
  `systemctl --user status <name>`, `journalctl --user -u <name>`).

## Bringing up a session

Two commands bring a session up. To resume an existing conversation
(e.g. "bring up backend"):

```bash
~/.dotfiles/scripts/claude_tmux_run.sh load <name>[/<task>]
```

It is idempotent. `load <name>` resumes the conversation most recently
talked in under `<hostname>/<name>`, labeled or not, in the directory that
conversation belongs to; `load <name>/<task>` pins the conversation
carrying that label (found with `history`, below) and refuses when the
`<name>/<task>` session is live with a different one -- switching means
killing work in flight, which is the user's call. With no such
conversation it refuses and points at `new`.

To start a fresh conversation (e.g. "a new backend session"):

```bash
~/.dotfiles/scripts/claude_tmux_run.sh new <name>[/<task>] <dir>
```

It always starts fresh, whatever the name already owns -- `new backend`
beside a live `backend/fix-login` gives an unlabeled `backend` --
and refuses when the session of that exact name is live, or when the
label already belongs to a conversation (load that one). `<dir>` is
required; ask which directory if it was not said and no earlier
conversation of the name shows it (`history`). Both run sessions in auto
permission mode with Remote Control enabled. Append `--dangerous` only
when the user explicitly asks for a session with permissions bypassed --
never choose it yourself.

One LIVE session per FULL name, label included: `api`, `api/login` and
`api/docs` are three names and run side by side, each in a session of its
own name; a second session of one of them is what must not exist. Never
launch a session by hand (`tmux new-session ... claude`); `new` and `load`
start one beside its siblings and refuse a second session of an exact
name.

One name can own SEVERAL conversations: a `/clear` inside a session, or
a `new` under a used name, starts a fresh conversation beside the old
one, and `load` resumes whichever was talked in last (by last message,
not file time: a picker rename touches a file without anyone talking in
it). A resumed id that differs from the one resumed earlier that day is
therefore normal, not a bug -- but say so when it happens, since the user
may have wanted the older thread. An unlabeled conversation that is not
the newest under its name is reached only by `load --id`, so label work
once its task is clear. To see them all, newest first, each with its label and opening
prompt:

```bash
~/.dotfiles/scripts/claude_tmux_run.sh history <name>
```

Resuming a specific older one is `load <name>/<task>` when it is labeled,
else `load --id <id>` with an id from `history` (any of a conversation's
ids: a resume continues it in a new transcript, and the newest is
resumed). When two conversations carry one label, `load <name>/<task>`
refuses and lists both ids: load the right one with `--id`, and relabel
the other. Never resume by hand with `claude --resume`: that skips the
double-open guard and the session naming.

Before starting a NEW conversation, list what already exists:

```bash
~/.dotfiles/scripts/claude_tmux_run.sh conversations [pattern]
```

A session name says nothing about the directory behind it -- work on a
subfolder is usually done from a session rooted higher up, so the history
for `proj/sub/tool` lives in `alpha`, rooted at
`~/work`. `new` under a name nobody used before always succeeds,
so a name that merely sounds right silently creates an empty second
conversation next to the one holding the work. If the listing shows a
plausible owner under another name, say so and offer it rather than
starting from nothing.

To stop a session:
`~/.dotfiles/scripts/claude_tmux_run.sh stop <name>[/<task>]`. It kills
the session of exactly that name and nothing else: a labeled session holds
a different conversation, so `stop backend` never reaches
`backend/fix-login` -- pass the full name. When nothing matches it
lists the labeled sessions under that name. Never
`tmux -L claude kill-session -t <name>`: a bare tmux target prefix-matches
ANY session, so with `api` gone it kills `api3`. `status` prints the
exact names. `capture-pane` does NOT accept the `=name` exact form ("can't
find pane") -- resolve pane ids first with
`tmux -L claude list-panes -a -F '#{session_name} #{pane_id}'`.

## Reloading sessions after a Claude Code update

Reload with `~/.dotfiles/scripts/claude_tmux_run.sh restart <name>[/<task>]`
(the exact name, as `status` prints it). It ends the old claude and resumes
the same conversation in the same tmux pane, with the permission mode the
session was launched with, so attached clients stay where they are. The
user does the same from tmux with `prefix C-r` on the session in view.
The conversation is unchanged, though a resume writes into a NEW transcript
file, so its id can differ from the one you saw before (see above). Each
restart logs its steps under `~/.dotfiles/.logs/<UTC>_claude_tmux_restart/`.

`restart` refuses a BUSY session and leaves it running: a turn, or a
background shell claude still tracks, which `claude agents` also reports
as busy, the turn long over. `--check` prints that work without
restarting, followed by the detached processes the restart would end
(`, and 1 detached process(es): cloud-sql-proxy`), which never refuse;
`--force` restarts over the work -- only on the user's say, after
reading the pane. `prefix C-r` puts both in its y/n prompt.

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
  systemd was detached on purpose (`setsid nohup ... > log`): nothing was
  tracking it, so it is NOT a reason to skip, but the restart ends it with
  the old claude's scope (see The setup). Name such processes in the report
  (`restart --check` lists them), so the user can start again what still
  matters. Grep the session's transcript for how it was launched before
  believing an env stamp.

`restart` finds both itself (a tracked shell is a child of claude's pid);
the list says what the pane shows when it refuses. Reload the idle ones,
then name the ones you skipped and why, and offer to come back for them
once they go quiet.

Which build each session actually runs:

```bash
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
  intact: effort drops to the configured default (`modelSettings` in
  `home/.claude/settings.json`) and the session's cwd returns to its
  launch directory. Report both so the user can restore
  them.
- This manager session cannot reload itself: it is in a turn whenever it
  runs anything, so `restart manager` refuses. Tell the user to press
  `prefix C-r` in its pane once it is idle, or run
  `systemctl --user restart claude-tmux`, which recreates the session and
  resumes this conversation. Either ends what the manager left running in
  the background (see The setup). A pulled change to the unit file
  needs `systemctl --user daemon-reload` first (`dotup` runs it); until then
  a restart runs the unit as systemd last read it.
- A pulled change to `home/.tmux.conf` (a hook, the title format) reaches
  the claude sessions' server only on
  `tmux -L claude source-file ~/.tmux.conf`: a plain `tmux source-file`
  reloads the default server, and nothing reloads either on its own.

Never run `claude_tmux_run.sh serve` -- that is the systemd entrypoint,
which blocks forever in a watch loop (a bare call only prints the usage)
-- and never `pkill -f` on
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
`~/.hov-dotfiles-private`. If that directory is missing, the repo is not cloned
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

Every fleet VM -- new and existing, CPU and GPU alike -- runs docker on
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
healthy.
CPU boxes are not exposed to that bug, but carry the policy anyway for
uniformity, and because mid-run unattended upgrades contend with
benchmarks. Boot-time upgrades keep boxes patched when no workload exists
yet.

How:

- `"exec-opts": ["native.cgroupdriver=cgroupfs"]` merged into
  /etc/docker/daemon.json, then restart docker (idle box only). Verify
  with `docker info --format '{{.CgroupDriver}}'`.
- `apt-daily-upgrade.timer` disabled;
  `systemctl add-wants multi-user.target apt-daily-upgrade.service` so
  apt's own unit runs at boot, plus a docker.service drop-in
  (/etc/systemd/system/docker.service.d/wait-apt-upgrade.conf:
  After=apt-daily-upgrade.service) so no container can exist while the
  boot upgrade's daemon-reload fires. After= only, no Wants=: the upgrade
  is a oneshot that does not stay active, so Wants= would rerun it on every
  docker restart, with docker down until it finished. apt-daily.timer (the
  download half) stays enabled.
- No wrapper unit. Boxes set up before 2026-10-07 have
  apt-upgrade-on-boot.service (a oneshot running `systemctl start
  apt-daily-upgrade.service`) instead: migrate them (disable and delete it,
  delete /etc/needrestart/conf.d/apt-upgrade-on-boot.conf if present, point
  the docker drop-in at apt-daily-upgrade.service, add-wants as above).
  That wrapper deadlocks for its 15 min timeout when an upgrade makes
  needrestart restart it (its own process maps the upgraded libs, and the
  restart waits on the upgrade that waits on needrestart), and exits early
  (docker then starts mid-upgrade) when needrestart re-executes systemd.
  needrestart already skips apt-daily-upgrade.service itself.
- WALinuxAgent stays at its default self-update behavior (goal-state
  driven, Azure's schedule); do not disable it: the agent package ships
  from -updates, which unattended-upgrades' security-only origins never
  install, so "boot-time agent updates" would really mean "no agent
  updates". Its occasional
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
zero instances exposes no CUDA devices.

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
- Permissions bypass is reserved for this manager session and for
  sessions the user explicitly requested with it (`--dangerous`).
- Never use background agents in this flow. Every session is an interactive
  Claude Code process in a tmux window, started by `claude_tmux_run.sh`.
  Do not run `claude --bg`, do not dispatch work from the `claude agents`
  view, and do not leave a daemon running: a background agent holds the
  conversation's transcript open, so the next load of that name is refused
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
  `claude agents --json` prints a refusal and exits 0, so the load guard
  calls it via `env -u CLAUDE_CODE_DISABLE_AGENT_VIEW` -- keep that wrapper,
  or the guard goes blind and double-opens a conversation.
- A turn can resume long after the previous one, on a machine that rebooted
  in between: the VM gets deallocated and started again, and systemd
  recreates this session. Before explaining current state by something you
  did earlier, re-establish the clock -- `date`, `uptime -s`,
  `journalctl --list-boots`. A VM running now is not evidence that an
  earlier deallocate failed.
