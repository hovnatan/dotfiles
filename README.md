My linux config files

## Layout

`home/` mirrors `$HOME`: each entry is installed at the same relative path
under `~`, e.g. `home/.vimrc` -> `~/.vimrc`, `home/.config/git` ->
`~/.config/git`, `home/Library/LaunchAgents/com.hovnatan.keyremap.plist` ->
`~/Library/LaunchAgents/com.hovnatan.keyremap.plist`. A few entries are
installed selectively or handled specially (`~/.zshrc` / `~/.zprofile` /
`~/.profile` are appended to rather than linked; `home/.profile.shared` is the
environment every login shell reads, bash or zsh).

`home/AGENTS_global_instructions.md` is the one canonical agent policy,
installed under whatever name each tool reads; `scripts/setup_user_symlinks.sh`
lists the links and why each name. Edit that file; every tool sees the change.
Situational policy (remote runs, ntfy) lives in skills under
`home/.claude/skills/`, which Codex also sees via `~/.agents/skills`.

Everything outside `home/` is repo tooling that never lands in `$HOME`:
`scripts/` (all executables, invoked by absolute path), `claude_tmux_session/`,
`nix/`, `apt/`, `docs/` (handoffs for one-off migrations), `.devcontainer/`,
`docker/`. `scripts/setup_user_symlinks.sh` performs the install and is the
authoritative map of what goes where. Nothing in this repo is on `PATH`;
`~/.local/bin` is the PATH directory.

To setup standalone:

```bash
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user_standalone.sh -o ~/setup_user_standalone.sh
bash -x ~/setup_user_standalone.sh
```

For setup symlinks:

```bash
git clone https://github.com/hovnatan/dotfiles.git ~/.dotfiles
bash -x ~/.dotfiles/scripts/setup_user_symlinks.sh
```

## Updating a machine after another one pushed

On the machine that is behind:

```bash
dotup            # alias for ~/.dotfiles/scripts/update.sh
```

It fast-forwards `~/.dotfiles` (and the private repos `~/.dotfiles-private` and
`~/.hov-dotfiles-private` when cloned) from origin, prints the pulled commit
range, re-runs `setup_user_symlinks.sh` so new files get linked, reports
Brewfile drift (macOS) or Aptfile drift (Ubuntu; see "Apt packages"), applies
the pinned Nix package set (where Nix is installed; see "Nix packages"), and
lists what to reload (tmux, Hammerspoon, open shells). Dirty tracked files are
stashed around the pull and popped after; a pop conflict stops the run with the
paths listed and the stash kept. Local commits not on origin make it refuse:
push or rebase them first. The installer is safe to re-run; anything that needs
a decision (IINA key bindings differing from the repo, a real directory where a
skill link belongs) is reported as a warning and makes the run exit non-zero
once the rest is done.

## Checks before a push

`scripts/check.sh` runs every check CI runs (shellcheck, shfmt, stylua, ruff, biome,
fish/JSON/nvim config, markdownlint, yamlfmt/yamllint/actionlint, the Nix flake, the
tests in `scripts/tests/`); the CI workflows call it too. The installer sets
`core.hooksPath` to `scripts/git-hooks`, whose `pre-push` runs
`check.sh lint` on each commit being pushed, in a throwaway worktree: the
linters, a few seconds. A failure stops the push; `git push --no-verify` skips
it once. The flake check and the tests are left to CI, so a push that breaks one
lands and CI reports it after; `check.sh --changed <paths>` runs the lint and
the tests whose `# check.sh covers:` line names a changed path, for a change
worth testing first. The script's header says how each piece is picked.

The Linux-only tests are skipped on a Mac. `vagrant/Vagrantfile` runs them there, in a
local Ubuntu guest with the Nix set, Docker and a copy of the working tree; its header
has the commands.

## Nix packages

Command-line tools come from Nix, the same set at the same versions on
Linux boxes and Macs (since 2026-09-23; the `Brewfile` keeps only the casks,
App Store apps and VS Code extensions). The curated list is `nix/flake.nix`:
almost everything is in its `common` list, and the per-OS lists hold the
exceptions (only zsh, Linux-only, as macOS ships its own). `nix/flake.lock`
pins the nixpkgs revision, so every machine that applies the same commit
gets the same builds. Nix's copy wins over the distro's (`~/.nix-profile/bin`
precedes `/usr/bin`), but not over `~/.local/bin`: a self-installed `uv`
there shadows Nix's. Opt-in per machine; set up on vm
(Ubuntu 24.04, x86_64) on 2026-09-23.

Install Nix, multi-user with a daemon (needs sudo). The versioned URL pins
the installer and the Nix it installs; drop the version from the path
(`https://nixos.org/nix/install`) to get the current release instead:

```bash
sh <(curl -fsSL https://releases.nixos.org/nix/nix-2.35.2/install) --daemon --yes
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon                              # Linux
sudo launchctl kickstart -k system/org.nixos.nix-daemon        # macOS
exec zsh -l                                  # a shell that has Nix on PATH
nix profile add path:$HOME/.dotfiles/nix     # the pinned package set
```

On a Mac that had the formulae from Homebrew, retire those copies once the
Nix set is in (`which -a tmux` lists both until then; whichever comes first
on PATH wins):

```bash
dscl . -read ~ UserShell    # must not be /opt/homebrew/bin/bash before bash goes
brew autoremove --dry-run   # see the Brewfile header: uninstall autoremoves deps
brew uninstall azure-cli bash gh googleworkspace-cli htop hunspell imagemagick \
  lftp media-info mosh node pandoc poppler rclone rsync shellcheck tmux typst uv wget
```

npm globals keep working: `home/.npmrc` puts them under `~/.local`, not in
Node's (now read-only) prefix. `az extension list` is worth a look after the
switch, since extensions were installed against brew's azure-cli.

Adding a package, applying a new lock and bumping nixpkgs are in the header
of `nix/flake.nix`. `dotup` applies the committed list and lock on every
machine that has the set installed (`nix profile upgrade`), and fails if Nix
is installed but missing from PATH. Uninstalling Nix:
<https://nix.dev/manual/nix/stable/installation/uninstall.html>

What the installer changes: `/nix`, the `nixbld` group and its build users,
`/etc/nix/nix.conf`, the `nix-daemon.service`/`.socket` units, and a hook
in `/etc/bash.bashrc`, `/etc/bashrc`, `/etc/zshrc`, `/etc/zsh/zshrc` and
`/etc/profile.d/nix.sh`. It saves the originals of edited files as
`*.backup-before-nix`. On macOS it also creates a separate APFS volume for
`/nix` and runs the daemon from launchd (`org.nixos.nix-daemon`).

Which shells get `~/.nix-profile/bin` on PATH, and how:

| Shell | Reached through |
| --- | --- |
| interactive bash / zsh | installer hook in `/etc/bash.bashrc`, `/etc/zsh/zshrc` |
| login bash | `/etc/profile` -> `/etc/profile.d/nix.sh` |
| login zsh, incl. the claude-tmux service's `$SHELL -lc` when the account's shell is zsh | `home/.zprofile` (Ubuntu's zsh never reads `/etc/profile`) |
| macOS zsh, login or not | installer hook in `/etc/zshrc`, plus `home/.zprofile` |
| systemd units that run no shell | none: use absolute paths |

Gotchas:

- The installer runs `systemctl daemon-reload`. On a GPU box not yet
  switched to docker's cgroupfs driver, that kills CUDA inside running
  containers (fleet policy in `claude_tmux_session/fleet.md`): install
  only while no GPU container is running.
- A running tmux server keeps the binary it was started with, and mixing
  versions works one way only (checked 2026-09-23): a 3.7c client talks to
  a 3.4 server, but a 3.4 client (apt's `/usr/bin/tmux`) against a 3.7c
  server fails with "server exited unexpectedly" -- the server is fine, the
  client is on the wrong PATH. Contexts without the Nix PATH (non-login
  shells, systemd's own PATH) still resolve `/usr/bin/tmux`.
- `nix profile add nixpkgs#foo` installs an unpinned package that no other
  machine knows about. Add it to `nix/flake.nix` instead.

## Apt packages

What Nix cannot give an Ubuntu box comes from apt: daemons and whatever else
has to be wired into the system. The curated list is `apt/Aptfile`, the
Brewfile's counterpart; today it holds Docker (the engine with its buildx
and compose plugins, from Docker's own repository). Its header has the
format, how to add a package or a repository, and the gotchas.

```bash
~/.dotfiles/scripts/apt_bundle.sh check      # what the Aptfile lists and the box lacks
~/.dotfiles/scripts/apt_bundle.sh install    # add the repositories, install what is missing (sudo)
```

`dotup` prints the `check` report on Ubuntu and never installs. The script
does nothing past the packages: the docker group, `/etc/docker/daemon.json`
and the fleet policy in `claude_tmux_session/fleet.md` stay separate steps.

## Claude Code in tmux from boot (VMs)

Starts a manager tmux session `manager` at boot: Claude Code with
permissions bypassed, started in `~/.dotfiles/claude_tmux_session`. Nothing
watches it after: a manager that quits leaves its shell at a prompt, the
session up, until you bring it back (below). Ask it (e.g. over Remote Control) to open
other sessions: per the `tmux-session` skill (`home/.claude/skills/tmux-session/`, which
any claude on any machine follows, not the manager alone) it opens a tmux session `<name>`
in a folder and starts claude there, or resumes a named conversation, in auto permission
mode (permissions bypassed only on explicit request).
`/resume` and `/rename` are yours from there. No session is
recreated when it exits, and the service's restarts and stops leave every
session alone. Opt-in per machine:

```bash
bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh
```

On a fresh machine, run `claude` once in `~/.dotfiles` first and accept the
workspace trust dialog; the manager starts inside the repo and would
otherwise sit at that prompt, invisible, in its detached pane. Window 0 of
every session is a plain shell with claude typed into it: quitting claude
keeps the session, and `claude --resume` there brings it back. The boot start
opens a new conversation. Remote Control and the agent view are set for every
claude in `home/.claude/settings.json`.

A claude is named `<machine>/<session>` (`vm/manager`), which is what Remote Control and
a phone notification show; the tmux session is `<session>` alone. `<machine>` is what
`scripts/machine_name.sh` prints: the machine's host name up to its first dot, or, for a
machine whose host name says nothing (a Mac's is `Mac`), the one line of
`~/.config/dotfiles/machine-name`, kept per machine in the personal private repo
(`machines/<name>/home/.config/dotfiles/machine-name`). Terminal titles lead with the
same name, `(vm) [manager]` in tmux (its bar too) and `(vm) fish: ~/x` outside it, as
does fish's prompt. A claude started with no name is listed in Remote Control under one
Claude Code makes up, `vm-enumerated-harbor`: the same `<machine>` in front, through
`CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX` (`home/.profile.shared`).

To also run a Remote Control server (`claude remote-control`) in a second window
of `manager`, name its folder in `~/.config/claude-tmux/remote-control-dir`, as an
absolute path. With no file there is no window; a path that is not a folder fails the
start. The next start of a `manager` session reads it. Answer two one-time prompts
first, or the server waits at them, invisible in its detached window: run `claude` in
that folder and accept the trust dialog, then `claude remote-control` and answer
`Enable Remote Control?` with `y`.

Keep the file in the personal private repo, one per machine, where the installer links
its directory into `~/.config` (a directory already there by hand is reported, and
goes first):

```bash
d=~/.dotfiles-private/machines/<name>/home/.config/claude-tmux
mkdir -p "$d" && echo "$HOME/<folder>" >"$d/remote-control-dir"
```

On a machine without that repo, write `~/.config/claude-tmux/remote-control-dir` by hand.

```bash
tmux attach -t manager                 # attach (any session name works)
tmux ls; pgrep -a -x claude            # is it up? (sessions, and claude in them)
systemctl --user start claude-tmux     # start the manager if its session is gone
journalctl --user -u claude-tmux       # what the boot start did
tmux kill-session -t =manager          # stop the manager (until the next boot)
systemctl --user disable claude-tmux   # no manager at boot any more
sudo loginctl disable-linger $USER     # also stop the user manager at boot
```

To leave the manager running, detach (prefix `d`) rather than quitting it.
Since the manager runs with permissions bypassed from boot, only enable this
on a machine whose SSH access you trust.

## tmux snapshots: sessions back after a reboot

Every tmux server in tmux's own socket folder snapshots its sessions every 10 minutes: each
session, its windows in order, and the directory of each window's active pane. Not the
programs, the splits or the text. `home/.config/tmux/tmux.conf` starts one
`scripts/tmux_server_arrangement.py run` per server; it ends with the server, and `dotup`
sends it SIGHUP to run on the pulled code. A snapshot the same as the one before is not
written; two weeks of them are kept. They are plain text, in
`~/.local/state/tmux_server_arrangements/<socket>/auto-<UTC time>.txt`, to read or edit by
hand.

```bash
~/.dotfiles/scripts/tmux_server_arrangement.py list              # what is saved
~/.dotfiles/scripts/tmux_server_arrangement.py restore           # after a reboot
~/.dotfiles/scripts/tmux_server_arrangement.py save <name>       # keep this layout
~/.dotfiles/scripts/tmux_server_arrangement.py replace <name>    # it, and nothing else
```

`restore` with no name takes the newest snapshot from before this server started: after a
reboot, the old server's last state. It creates each saved session that is not open, a
window per saved one, each a fresh shell in its directory; a session already open
(`manager`, at boot) is left as it is. `replace` also closes every other session, and
refuses before touching anything if one of them holds the command itself, or has a pane
whose foreground command line is more than a bare shell (`claude ...`, `nvim ...`, `bash
build.sh`). A job left in the background (`cmd &`) is not seen, and dies. A saved directory
that is gone stops either before anything opens. `-L <name>` after the verb picks another
server. Each run logs to
`~/.dotfiles/.logs/<UTC>_tmux_server_arrangement/events.log`.
