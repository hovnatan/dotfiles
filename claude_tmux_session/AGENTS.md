# Claude Code tmux manager session

This directory is the working directory of the "manager" tmux session
started at boot by claude-tmux.service (see
`../home/.config/systemd/user/claude-tmux.service` and
`../scripts/claude_manager_start.sh`). That session runs Claude Code with
permissions bypassed and acts as the manager for the other Claude Code tmux
sessions on this machine.

## The setup

- All sessions live on the default tmux server, so plain `tmux ...` reaches
  them, beside anything started there by hand. `tmux kill-server` ends every
  one of them.
- Only the "manager" session comes from systemd: the service starts it at
  boot, and on `systemctl --user start claude-tmux` when its session is
  missing. Nothing watches it after; nothing recreates it, or any other
  session, that exits. Every other session is created on demand -- by you,
  when asked. Stopping or restarting the service leaves every session alone.
- Every claude on this machine starts with Remote Control on, the agent view
  off and auto permission mode, from `home/.claude/settings.json`: no flags to
  pass for those.
- tmux session names are short (letters, digits, `-` and `_` only; the
  window title shows the first two characters). The Claude Code conversation
  behind a session is named `<hostname>/<session name>`. A conversation has
  ONE name: the prompt bar, `/list-agents` (what SendMessage addresses), the
  `/resume` picker and claude.ai all show it, and `/rename` from any of
  them changes it everywhere; claude.ai lists every machine's sessions,
  hence the hostname. Pass the name with `-n` on every launch, resumes
  included (a resume by id alone reverts the peer name to an auto-generated
  directory-based one). If a running session still shows an auto-generated
  peer name, `/rename <hostname>/<session name>` inside it fixes it live.
- Until 2026-10-22 the form was `<hostname>-<session name>`, and older
  conversations and running sessions still carry it. The search below finds
  them, and a resume with `-n` renames one to the `/` form. Address a running
  one by the name `ListAgents` shows.
- A conversation is LABELED with its task once the task is clear:
  `/rename <hostname>/<session name>/<task>` inside the session (task: the
  session-name alphabet, letters, digits, `-` and `_`, e.g.
  `vm/backend/fix-login`), or `Ctrl+R` on its row in the
  `/resume` picker for a finished one. The label is what the picker, the
  prompt bar, the status line and claude.ai show; without it every
  conversation a name accumulates (one per `/clear`) reads the same. The
  peer name carries the label too, so address a labeled session by its
  full name (`ListAgents` shows it). A resume keeps the label only when `-n`
  carries it, and `/clear` keeps it: the fresh conversation inherits it, so
  relabel it (or `/rename` back to the bare name) once its own task is clear.
- A tmux session keeps the name it was created under: a `/rename` changes
  the conversation's name, not the session's, so session `backend` can hold
  `<hostname>/backend/fix-login`. tmux targets without `=` prefix-match;
  `=backend` matches exactly that name.
- A prompt-bar color (`/color`) does not survive `/clear`; only a resume
  brings it back (Claude Code does that itself).
- What a pane starts ends with it, in every tmux pane on this machine. Each
  pane runs in a systemd scope of its own, and when a pane closes, however it
  closes (its program exits, `kill-pane`, `kill-window`, its session closing),
  its scope is stopped (`home/.config/tmux/reap-panes.sh`, logged in the tmux
  hooks' log): a `setsid nohup` job, a proxy, a watcher started from a pane
  does not survive it. A job meant to outlive its pane runs as a unit of its
  own: `systemd-run --user --unit=<name> <command>` (then
  `systemctl --user status <name>`, `journalctl --user -u <name>`).
- Window 0 of a session is a plain shell, and claude is a command typed into
  it. Claude quitting or crashing leaves that shell at its prompt and the
  session up, windows and clients included, until claude is typed in again.
- A session may hold more windows: the user opens nvim or a shell beside it
  (`prefix C`; Cmd-J/K switch). Keep to one `claude` per session, the
  manager's Remote Control window aside.
- On a machine whose `~/.config/claude-tmux/remote-control-dir` names a folder,
  the manager's start also opens window `remote-control` there, with
  `claude remote-control --spawn=same-dir --name <hostname>/remote-control` typed
  into its shell.
  It lets claude.ai and the phone start sessions in that folder, in the
  settings' permission mode, and those sessions are not tmux sessions. A server
  that exits stays at its shell, nothing restarts it, and a `manager` session
  already up is left as it is: type that command there, or open the window by
  hand, when it is missing.
- A manager claude that quits stays at its shell; resume it there like any
  session, with `--dangerously-skip-permissions`. With the session gone,
  `systemctl --user start claude-tmux` starts it again. That start, and each
  boot, opens a NEW conversation; the earlier ones stay on disk to resume.

## Bringing up a session

Sessions are plain tmux, and nothing guards them: the checks below are yours
to make. First see what runs, as nothing here refuses to open a conversation
that is already open. `-n` in each claude's arguments is the name it was
launched under; a later `/rename` does not show there:

```bash
tmux ls
pgrep -a -x claude
```

Then see what exists under the name, most recently written first (the id is
the file name, the second line the conversation's directory):

```bash
grep -lE "\"customTitle\":\"$(hostname)[/-]<name>[/\"]" ~/.claude/projects/*/*.jsonl | xargs -r ls -t
grep -m1 -o '"cwd":"[^"]*"' <file>
```

A session name says nothing about the directory behind it -- work on a
subfolder is usually done from a session rooted higher up, so the history
for `proj/sub/tool` lives in `alpha`, rooted at `~/work`. Before starting a
NEW conversation, also search by directory or topic across all of
`~/.claude/projects`. A name that merely sounds right silently creates an
empty second conversation next to the one holding the work. If the search
shows a plausible owner under another name, say so and offer it rather than
starting from nothing.

To start a fresh conversation (e.g. "a new backend session"), with `<dir>`
an absolute path; ask which directory if it was not said and no earlier
conversation of the name shows it:

```bash
tmux new-session -d -s <name> -c <dir>
tmux send-keys -t '=<name>:0' "claude -n $(hostname)/<name>" Enter
```

To resume one (e.g. "bring up backend"), open the session in the
conversation's directory and type the resume, with the full name, label
included. A resume only finds a conversation from its own directory. When
the session is up with its claude gone, skip the `new-session`:

```bash
tmux new-session -d -s <name> -c <dir>
tmux send-keys -t '=<name>:0' "claude --resume <id> -n $(hostname)/<name>[/<task>]" Enter
```

`:0` is claude's shell only while that shell lives: when it exits with another
window open, `renumber-windows` makes that window 0, and typed keys go into nvim
or `claude remote-control`. In a session already up, check first that window 0
shows the shell (`fish`):

```bash
tmux list-windows -t '=<name>:' -F '#I #W #{pane_current_command}'
```

Append `--dangerously-skip-permissions` only when the user explicitly asks
for a session with permissions bypassed -- never choose it yourself.

One LIVE session per FULL name, label included: `api`, `api/login` and
`api/docs` are three names and run side by side, each in a session of its
own name; a second session of one of them is what must not exist.

One name can own SEVERAL conversations: a `/clear` inside a session, or a
fresh start under a used name, starts a new conversation beside the old one.
Pick by last message, not file time (a picker rename touches a file without
anyone talking in it), and say which you resumed, since the user may have
wanted the older thread. A resume continues a conversation in a new
transcript, so its id can differ from the one seen before.

To stop a session: `tmux kill-session -t '=<name>'`, with the `=`: a bare tmux
target prefix-matches ANY session, so with `api` gone it kills `api3`.
`capture-pane` does NOT accept the `=name` exact form ("can't find pane") --
resolve pane ids first with `tmux list-panes -a -F '#{session_name} #{pane_id}'`.

## Reloading sessions after a Claude Code update

A session runs a new build only once its claude starts again. Reload one by
exiting its claude and resuming it in the same shell. The session, its other
windows, attached clients and what its panes started all stay; only the claude
process goes. Read its flags first, as `pgrep -a -x claude` is the only record
of them, and pass `--dangerously-skip-permissions` back only for a session that
had it:

```bash
tmux send-keys -t <pane id> /exit Enter
shell=$(tmux display -p -t <pane id> '#{pane_pid}')
while pgrep -P "$shell" -x claude >/dev/null; do sleep 1; done
tmux send-keys -t <pane id> "claude --resume <id> -n $(hostname)/<name>[/<task>]" Enter
```

The wait matters: keys sent while claude shuts down are lost in its exiting
screen, which leaves a bare prompt that looks reloaded. An exit can take 30
seconds; past that, look at the pane rather than typing on.

A session launched before window 0 became a shell has no shell under its
claude: exiting ends the session, windows and all, and it then has to be
started anew. To tell the two apart, read `pane_start_command`: `fish` for a
shell-first pane, and it holds `exec claude` for the older kind.

Reload only IDLE sessions. Nothing checks or refuses: exiting ends what claude
is running, so these checks are the only guard. A reload buys a fresh
binary; it is never worth killing work in flight, and "reload all sessions"
does not authorise that. Capture every target's pane first and leave a
session alone when it shows:

- a turn in progress -- a spinner with an elapsed timer at the bottom.
  Capture twice a few seconds apart: an advancing timer means it is
  working, not stuck, however long it has been going.
- a background shell, watcher or Monitor the harness still TRACKS -- killing
  one leaves no completion record, so the resumed session only learns the
  command "may have been running when the process exited" and has to redo it.
  Tracked means a live CHILD of the session's `claude` pid. A process merely
  carrying that session's `CLAUDE_PID`/`TMUX_PANE` env but reparented to
  systemd was detached on purpose (`setsid nohup ... > log`): nothing was
  tracking it, so it is NOT a reason to skip: its pane stays, so it survives
  the reload (a session of the older kind closes, and ends it; see The
  setup). Grep the session's transcript for how it was launched before
  believing an env stamp.

Reload the idle ones, then name the ones you skipped and why, and offer to
come back for them once they go quiet.

Which build each session actually runs:

```bash
tmux list-panes -a -F '#{session_name} #{pane_pid}' |
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
  batch and reload the stragglers.
- An exit discards text the user typed into the prompt but never sent, and
  `/exit` sent on top of it is not a command -- but
  the input box ALSO renders Claude Code's suggested-action hint, which
  echoes the recap's next step ("commit this" under a recap ending "next is
  committing them"). `capture-pane -p` strips the styling that separates the
  two, so a line in the box is not proof of pending input. Quote it back and
  ask; never skip a reload over it. (`-e` keeps the SGR codes to compare.)
- A pane in copy mode takes typed keys as copy-mode commands. Check
  `#{pane_in_mode}` is 0 before typing into one.
- A reload resets per-process runtime state even though the conversation is
  intact: effort drops to the configured default (`modelSettings` in
  `home/.claude/settings.json`) and the session's cwd returns to its
  launch directory. Report both so the user can restore
  them.
- This manager session cannot reload itself: exiting ends the turn doing the
  reload, before its resume. Tell the user to `/exit` it once it is idle, then
  resume it in its shell, with `--dangerously-skip-permissions`. Restarting
  the service does not reload it: the service only starts a manager whose
  session is missing. A pulled change to the unit file needs
  `systemctl --user daemon-reload` (`dotup` runs it) before the next boot or
  restart uses it.
- A pulled change to `home/.tmux.conf` (a hook, the title format) reaches
  the server only on `tmux source-file ~/.tmux.conf`: nothing reloads it on
  its own.

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
  sessions the user explicitly requested with it
  (`--dangerously-skip-permissions`).
- Never use background agents in this flow. Every session is an interactive
  Claude Code process in a tmux window.
  Do not run `claude --bg`, do not dispatch work from the `claude agents`
  view, and do not leave a daemon running: a background agent holds the
  conversation's transcript open, so a resume of it is refused
  ("already open in another claude process"), and the daemon respawns a
  worker you kill with a signal, under a new pid. Note that merely opening
  `claude agents` starts a transient daemon -- if you open it (it is the
  only way to stop one background agent without touching the others: select
  the row, `ctrl+x`), run `claude daemon stop --any` afterwards.
  `claude daemon stop --any` terminates every background session and the
  supervisor; interactive tmux sessions are unaffected.
- `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` is set in `home/.claude/settings.json`,
  which turns off `claude agents`, `--bg`, `/background` and the supervisor --
  including the left arrow that opens the agent strip, which otherwise starts
  a daemon and leaves a background session behind on every press.
- A turn can resume long after the previous one, on a machine that rebooted
  in between: the VM gets deallocated and started again, and systemd
  recreates this session. Before explaining current state by something you
  did earlier, re-establish the clock -- `date`, `uptime -s`,
  `journalctl --list-boots`. A VM running now is not evidence that an
  earlier deallocate failed.
