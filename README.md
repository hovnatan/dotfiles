My linux config files

## Layout

`home/` mirrors `$HOME`: each entry is installed at the same relative path
under `~`, e.g. `home/.tmux.conf` -> `~/.tmux.conf`, `home/.config/git` ->
`~/.config/git`, `home/Library/LaunchAgents/com.hovnatan.keyremap.plist` ->
`~/Library/LaunchAgents/com.hovnatan.keyremap.plist`. A few entries are
installed selectively or handled specially (`home/.config/zathura_light` ->
`~/.config/zathura`, and `~/.zshrc` / `~/.zprofile` / `~/.profile` are
appended to rather than linked; `home/.profile.shared` is the environment
every login shell reads, bash or zsh).

`home/AGENTS.md` is the one canonical agent policy, installed under whatever
name each tool reads; `scripts/setup_user_symlinks.sh` lists the links and
why each name. Edit `home/AGENTS.md`; every tool sees the change.
Situational policy (remote runs, ntfy) lives in skills under
`home/.claude/skills/`, which Codex also sees via `~/.agents/skills`.

Everything outside `home/` is repo tooling that never lands in `$HOME`:
`scripts/` (all executables, invoked by absolute path), `claude_tmux_session/`,
`nix/`, `docs/` (handoffs for one-off migrations), `.devcontainer/`, `docker/`. `scripts/setup_user_symlinks.sh` performs the
install and is the authoritative map of what goes where. Nothing in this repo
is on `PATH`; `~/.local/bin` is the PATH directory.


To setup standalone:

```
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user_standalone.sh -o ~/setup_user_standalone.sh
bash -x ~/setup_user_standalone.sh
```

For setup symlinks:

```
git clone https://github.com/hovnatan/dotfiles.git ~/.dotfiles
bash -x ~/.dotfiles/scripts/setup_user_symlinks.sh
```

## Updating a machine after another one pushed

On the machine that is behind:

```
dotup            # alias for ~/.dotfiles/scripts/update.sh
```

It fast-forwards `~/.dotfiles` (and `~/.dotfiles-private` when cloned) from
origin, prints the pulled commit range, re-runs `setup_user_symlinks.sh` so
new files get linked, reports Brewfile drift (macOS), applies the pinned
Nix package set (where Nix is installed; see "Nix packages"), and lists
what to reload (tmux, Hammerspoon, open shells). Dirty tracked files are
stashed around the pull and popped after; a pop conflict stops the run with the paths listed and the stash kept.
Local commits not on origin make it refuse: push or rebase them first.
The installer is safe to re-run; anything that needs a decision (IINA key
bindings differing from the repo, a real directory where a skill link
belongs) is reported as a warning and makes the run exit non-zero once the
rest is done.

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

```
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

```
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
https://nix.dev/manual/nix/stable/installation/uninstall.html

What the installer changes: `/nix`, the `nixbld` group and its build users,
`/etc/nix/nix.conf`, the `nix-daemon.service`/`.socket` units, and a hook
in `/etc/bash.bashrc`, `/etc/bashrc`, `/etc/zshrc`, `/etc/zsh/zshrc` and
`/etc/profile.d/nix.sh`. It saves the originals of edited files as
`*.backup-before-nix`. On macOS it also creates a separate APFS volume for
`/nix` and runs the daemon from launchd (`org.nixos.nix-daemon`).

Which shells get `~/.nix-profile/bin` on PATH, and how:

| Shell                                   | Reached through                                   |
|-----------------------------------------|---------------------------------------------------|
| interactive bash / zsh                  | installer hook in `/etc/bash.bashrc`, `/etc/zsh/zshrc` |
| login bash                              | `/etc/profile` -> `/etc/profile.d/nix.sh`         |
| login zsh, incl. the claude-tmux service's `$SHELL -lc` when the account's shell is zsh | `home/.zprofile` (Ubuntu's zsh never reads `/etc/profile`) |
| macOS zsh, login or not                 | installer hook in `/etc/zshrc`, plus `home/.zprofile` |
| systemd units that run no shell         | none: use absolute paths                          |

Gotchas:

- The installer runs `systemctl daemon-reload`. On a GPU box not yet
  switched to docker's cgroupfs driver, that kills CUDA inside running
  containers (fleet policy in `claude_tmux_session/AGENTS.md`): install
  only while no GPU container is running.
- A running tmux server keeps the binary it was started with, and mixing
  versions works one way only (checked 2026-09-23): a 3.7c client talks to
  a 3.4 server, but a 3.4 client (apt's `/usr/bin/tmux`) against a 3.7c
  server fails with "server exited unexpectedly" -- the server is fine, the
  client is on the wrong PATH. Contexts without the Nix PATH (non-login
  shells, systemd's own PATH) still resolve `/usr/bin/tmux`.
- `nix profile add nixpkgs#foo` installs an unpinned package that no other
  machine knows about. Add it to `nix/flake.nix` instead.

## Claude Code in tmux from boot (VMs)

Runs an always-on manager tmux session `claude` at boot: Claude Code with
permissions bypassed, started in `~/.dotfiles/claude_tmux_session`, restarted
whenever it exits. Ask it (e.g. over Remote Control) to bring up other
sessions: per `claude_tmux_session/AGENTS.md` it resumes the conversation
named `<hostname>-<name>` -- also its Remote Control name on claude.ai -- in
a tmux session `<name>` running in auto permission mode (permissions
bypassed only on explicit request). Spawned sessions are
unmanaged: they survive service restarts and stops, and nothing recreates one
that exits. Opt-in per machine:

```
bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh
```

On a fresh machine, run `claude` once in `~/.dotfiles` first and accept the
workspace trust dialog; the manager starts inside the repo and would
otherwise sit at that prompt, invisible, in its detached pane.

```
tmux -L claude attach -t claude            # attach (any session name works)
systemctl --user status claude-tmux        # is it up?
journalctl --user -u claude-tmux -f        # logs
systemctl --user stop claude-tmux          # stop until next boot
systemctl --user disable --now claude-tmux # off for good
sudo loginctl disable-linger $USER         # also stop the user manager at boot
```

Quitting claude inside the manager session makes systemd recreate it after
~10s. To leave it running instead, detach (prefix `d`) rather than quitting.
Since the manager runs with permissions bypassed from boot, only enable this
on a machine whose SSH access you trust.
