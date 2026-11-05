# Fleet VMs

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

A turn can resume long after the previous one, on a machine that rebooted
in between: the VM gets deallocated and started again, and systemd
recreates the manager session. Before explaining current state by something
you did earlier, re-establish the clock -- `date`, `uptime -s`,
`journalctl --list-boots`. A VM running now is not evidence that an earlier
deallocate failed.

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
