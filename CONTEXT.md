# Dotfiles

One public repo that every machine I use installs into `$HOME`, so a config
edit made on one machine reaches the others. This file is the glossary for
talking about that; `README.md` says how the pieces work.

## Language

**Install**:
Making `$HOME` on a machine point at this repo: links for everything under
`home/`, plus the few files that are appended to or copied. Done by
`scripts/setup_user_symlinks.sh`, which is also the authoritative map of
what goes where.
_Avoid_: Setup, bootstrap, link

**Update**:
Bringing a machine's clone to the latest published state on origin and then
re-installing, so files added since get linked. Done by `scripts/update.sh`
(alias `dotup`) on the target machine.
_Avoid_: Sync, pull (the git step is only half of it)

**Source machine**:
The machine on which a dotfiles edit was made and pushed.

**Target machine**:
The machine being updated. The update always runs on it; nothing is pushed
into a machine from elsewhere.
_Avoid_: Remote, second computer

**Machine-local file**:
A file that lives on one machine only and is in no repo, written there by
hand or by a tool: the git email in `~/.gitconfig`, the light/dark links
that `scripts/appearance.sh` points, fish universal variables.
The tracked counterpart includes or requires it. A reinstall of the machine
loses it.
_Avoid_: Private (that means the private companion repo), per-machine (that
one is in a repo)

**Machine name**:
The short name a machine goes by wherever it is shown: prompts, ssh tab
titles, claude sessions (`<machine>/<session>`), phone notifications. It is
the line of the per-machine file `~/.config/dotfiles/machine-name` where
there is one, else the host name up to its first dot;
`scripts/machine_name.sh` prints it.
_Avoid_: Host name (the system's own, a generic `Mac` on a Mac), and the
`<name>` of `machines/<name>/` (the key the install finds a machine's files
by)

**Per-machine file**:
A file for one machine only that is kept in the personal private repo, under
`machines/<name>/home/`, and linked by the install to the same path under
that machine's `$HOME`: `~/.ssh/local_config`,
`~/.hammerspoon/local_hammerspoon.lua`, the ntfy topic in
`~/.config/claude-ntfy/`, `~/.config/claude-tmux/remote-control-dir`,
`~/.config/dotfiles/machine-name`.
An update carries it, and a reinstall brings it back. On a machine with no
directory under `machines/`, the same path written by hand is a
machine-local file.
_Avoid_: Machine-local (that one is in no repo)

**Private repo**:
One of two optional companion clones for anything that should not be public,
updated alongside this repo when present: `~/.dotfiles-private` (personal:
the hunspell word list, the grammar-drill bank, each machine's own files
such as its ntfy topic) and `~/.hov-dotfiles-private` (work: the work log
config, internal documents, hosts).

**Vendored skill**:
A Claude Code skill copied into `home/.claude/skills/<name>/` and pinned by
its `.upstream` file.

**Plugin skill**:
A skill that resolves from an enabled plugin by bare name and is never copied
into `~/.claude/skills`, since a loose copy would shadow it and stop updating.
