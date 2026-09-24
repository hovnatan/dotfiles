# Nix's login hook lives in /etc/profile.d, which bash logins reach via
# /etc/profile but Ubuntu's zsh never reads; source it here so login zsh
# (e.g. the claude-tmux service's `$SHELL -lc` on an account whose shell is
# zsh) sees ~/.nix-profile/bin too.
# Runs before ~/.profile to keep bash's order: ~/.local/bin ahead of Nix.
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
[ -f ~/.profile ] && emulate sh -c '. ~/.profile'

# export ANTHROPIC_MODEL='claude-opus-5[1m]'
# export CLAUDE_CODE_EFFORT_LEVEL=max
export CLAUDE_CODE_SHELL=$HOME/.nix-profile/bin/bash
