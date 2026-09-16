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
A file that lives on one machine only and is never tracked: the git email in
`~/.gitconfig`, `~/.hammerspoon/local_hammerspoon.lua`, `~/.ssh/local_config`.
The tracked counterpart includes or requires it.
_Avoid_: Private (that means the private companion repo)

**Private repo**:
`~/.dotfiles-private`, the optional companion clone for anything that names
an internal document or host. Updated alongside this repo when present.

**Vendored skill**:
A Claude Code skill copied into `home/.claude/skills/<name>/` and pinned by
its `.upstream` file.

**Plugin skill**:
A skill that resolves from an enabled plugin by bare name and is never copied
into `~/.claude/skills`, since a loose copy would shadow it and stop updating.
