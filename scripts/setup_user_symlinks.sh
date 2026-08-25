#!/usr/bin/env bash

# set -e

# rm -rf ~/.tmux.conf ~/.zshrc ~/.bashrc_local ~/.vimrc ~/.bashrc_local ~/.config/htop ~/.ssh/config

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
# procps: `ps` is needed by .claude/notify-stop.sh and absent from slim images
$SUDO apt-get install -y --no-install-recommends curl wget sudo htop tmux zsh vim git openssh-client make locales procps
$SUDO locale-gen --no-purge en_US.UTF-8

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/home/.tmux.conf ~/.tmux.conf
mkdir -p ~/.tmux/logs

[ -L ~/.zshrc ] && rm -f ~/.zshrc
if ! grep -qs '\.dotfiles/home/\.zshrc\.shared' ~/.zshrc; then
cat <<EOT >> ~/.zshrc
if [[ -f "\$HOME/.dotfiles/home/.zshrc.shared" ]]; then
  source "\$HOME/.dotfiles/home/.zshrc.shared"
fi
EOT
fi

if ! grep -qs '\.dotfiles/home/\.zprofile' ~/.zprofile; then
cat <<EOT >> ~/.zprofile
if [[ -f "\$HOME/.dotfiles/home/.zprofile" ]]; then
  source "\$HOME/.dotfiles/home/.zprofile"
fi
EOT
fi

mkdir -p ~/.vimundo/
rm -rf ~/.vimrc
ln -s ~/.dotfiles/home/.vimrc ~/.vimrc

# Hunspell personal word list (technical terms). The name matches the en_US
# dictionary so hunspell finds it by default; WORDLIST in .zshrc.shared points
# here too, covering other locales. Interactive saves write through the link.
ln -sf ~/.dotfiles/home/.hunspell_en_US ~/.hunspell_en_US

# # Check if .bashrc_local is already sourced in .bashrc
# if ! grep -q '\.bashrc_local' ~/.bashrc; then
#     cat <<EOT >> ~/.bashrc
# if [[ -f "\$HOME/.bashrc_local" ]]; then
#     source "\$HOME/.bashrc_local"
# fi
# EOT
# fi
# rm -rf ~/.bashrc_local
# ln -s ~/.dotfiles/home/.bashrc_local ~/.bashrc_local


rm -rf ~/.config/git
ln -s ~/.dotfiles/home/.config/git ~/.config/git

# Machine-local git config — not tracked in dotfiles. It pulls in the shared,
# tracked config.shared via [include], and also receives `git config --global`
# writes and tool injections (safe.directory, ...), keeping config.shared clean.
if ! grep -qs 'config\.shared' ~/.gitconfig; then
    echo -e "\033[33mAdd email to ~/.gitconfig\033[0m"
    cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.config/git/config.shared
[user]
  email =
# [core]
#   sshCommand = ssh -i ~/.ssh/hk_dev.pem -F /dev/null
[credential]
  helper = "!f() { echo \"username=x-access-token\"; echo \"password=\$GH_TOKEN\"; }; f"
# [url "https://github.com/"]
#   insteadOf = git@github.com:
EOT
fi

mkdir -p ~/.config
rm -rf ~/.config/htop
ln -s ~/.dotfiles/home/.config/htop ~/.config/

# cd ~
# ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
#chmod 644 ~/.ssh/config
# touch ~/.ssh/authorized_keys
# chmod 600 ~/.ssh/authorized_keys
mkdir -p ~/.ssh
ln -s ../.dotfiles/home/.ssh/config ~/.ssh/config

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt

# sudo gpasswd -a $USER docker

# mkdir -p ~/.config/Cursor/User
# ln -sf ~/Dropbox/scripts/Cursor/User/keybindings.json ~/.config/Cursor/User/keybindings.json
# ln -sf ~/Dropbox/scripts/Cursor/User/settings.json ~/.config/Cursor/User/settings.json

mkdir -p ~/.codex
ln -sf ~/.dotfiles/home/.codex/config.toml ~/.codex/config.toml

# Global agent instructions: one canonical file, home/AGENTS.md, installed
# under whatever name each tool reads. Claude Code reads only
# ~/.claude/CLAUDE.md (it ignores the AGENTS.md name); Codex reads
# ~/.codex/AGENTS.md. Add ~/.config/opencode/AGENTS.md if opencode is ever
# installed.
ln -sf ~/.dotfiles/home/AGENTS.md ~/.codex/AGENTS.md

mkdir -p ~/.claude
ln -sf ~/.dotfiles/home/AGENTS.md ~/.claude/CLAUDE.md
ln -sf ~/.dotfiles/home/.claude/settings.json ~/.claude/settings.json
ln -sf ~/.dotfiles/home/.claude/statusline-command.sh ~/.claude/statusline-command.sh
ln -sf ~/.dotfiles/home/.claude/keybindings.json ~/.claude/keybindings.json

# Private companion repo, cloned at ~/.dotfiles-private: anything naming an
# internal document or host lives there, not in this public repo. It is
# OPTIONAL - a machine without the clone still installs cleanly, it just has
# no work log routine.
if [ -d ~/.dotfiles-private/home/.config ]; then
  mkdir -p ~/.config
  for d in ~/.dotfiles-private/home/.config/*/; do
    [ -d "$d" ] || continue
    target=~/.config/"$(basename "$d")"
    # ln -sfn would drop the link INSIDE a real directory of the same name
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      echo -e "\033[33m$target is a real directory - leaving it, move its contents into the private repo\033[0m"
      continue
    fi
    ln -sfn "${d%/}" "$target"
  done
else
  echo "~/.dotfiles-private not cloned - skipping private config"
fi

# Claude Code personal skills — keep ~/.claude/skills as a real directory so
# skills installed by other means are left alone, and symlink in each skill
# vendored under .dotfiles/home/.claude/skills/ (pinned per skill via .upstream;
# see scripts/check_skill_updates.sh).
mkdir -p ~/.claude/skills
for skill in ~/.dotfiles/home/.claude/skills/*/; do
  [ -d "$skill" ] || continue
  ln -sfn "${skill%/}" ~/.claude/skills/"$(basename "$skill")"
done

# Expose the same skills under ~/.agents/skills for tools that look there.
mkdir -p ~/.agents
rm -rf ~/.agents/skills
ln -s ~/.claude/skills ~/.agents/skills

ln -s ~/.dotfiles/home/.config/ghostty ~/.config/

mkdir -p ~/.local/{bin,local}
ln -sf ~/.dotfiles/home/.npmrc ~/.npmrc

ln -sf ~/.dotfiles/home/.config/uv ~/.config/

# macOS only
if [ "$(uname)" = "Darwin" ]; then
  # IINA reads ~/.config/iina as its mpv config dir, incl. scripts/
  ln -sf ~/.dotfiles/home/.config/iina ~/.config/

  mkdir -p ~/.colima/default
  ln -sf ~/.dotfiles/home/.colima/default/colima.yaml ~/.colima/default/colima.yaml

  ln -sfn ~/.dotfiles/home/.hammerspoon ~/.hammerspoon
  if [ ! -f ~/Library/CloudStorage/Dropbox/Scripts/hammerspoon/local_config.lua ] \
      && [ ! -f ~/Dropbox/Scripts/hammerspoon/local_config.lua ]; then
    echo -e "\033[33mDropbox Scripts/hammerspoon/local_config.lua not found (Chrome profiles for Hammerspoon) - sync Dropbox or create it\033[0m"
  fi

  # Login key remaps (caps lock -> ctrl, PC menu key -> right option)
  mkdir -p ~/Library/LaunchAgents
  keyremap_label=com.hovnatan.keyremap
  ln -sf ~/.dotfiles/home/Library/LaunchAgents/"$keyremap_label".plist ~/Library/LaunchAgents/
  launchctl bootout "gui/$(id -u)/$keyremap_label" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/"$keyremap_label".plist

  # Preview markup colors (magenta annotations for LLM screenshot review)
  ~/.dotfiles/scripts/macos/setup_preview_markup.sh

  # Hunspell + en_US dictionary (brew ships no dictionaries)
  ~/.dotfiles/scripts/macos/setup_hunspell.sh
fi

echo "Done"
