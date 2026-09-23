#!/usr/bin/env bash

# Installs this repo into $HOME: symlinks for everything under home/, plus
# the few files that are appended to or copied instead. Safe to re-run: it
# is what scripts/update.sh (alias `dotup`) runs after every pull, so a step
# that would prompt, restart something, or stop the script on a re-run must
# be gated on the work actually being needed. A problem that needs a human
# decision is reported with warn() and the script carries on, exiting
# non-zero at the end, rather than leaving the rest of the machine
# half-installed over one unrelated file.

# set -e

# rm -rf ~/.tmux.conf ~/.zshrc ~/.bashrc_local ~/.vimrc ~/.bashrc_local ~/.config/htop ~/.ssh/config

failed=0
warn() {
  echo -e "\033[33mwarning: $*\033[0m" >&2
  failed=1
}

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi

# Debian/Ubuntu base packages. Only touch apt when one is missing, so a
# re-run on an installed box neither prompts for sudo nor waits on apt.
# procps: `ps` is needed by .claude/notify-stop.sh and absent from slim images
if command -v apt-get &> /dev/null; then
  missing=()
  for pkg in curl wget sudo htop tmux zsh vim git openssh-client make locales procps; do
    dpkg -s "$pkg" &> /dev/null || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update
    $SUDO apt-get install -y --no-install-recommends "${missing[@]}"
  fi
  if ! locale -a 2>/dev/null | grep -qi '^en_US.utf-\?8$'; then
    $SUDO locale-gen --no-purge en_US.UTF-8
  fi
fi

cd ~ || exit 1

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
ln -sfn ../.dotfiles/home/.ssh/config ~/.ssh/config

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
# under whatever name each tool reads. At user level Claude Code reads only
# ~/.claude/CLAUDE.md (since v2.1.277 it reads AGENTS.md in projects, never at
# user level); Codex reads
# ~/.codex/AGENTS.md. Add ~/.config/opencode/AGENTS.md if opencode is ever
# installed.
ln -sf ~/.dotfiles/home/AGENTS.md ~/.codex/AGENTS.md

mkdir -p ~/.claude
ln -sf ~/.dotfiles/home/AGENTS.md ~/.claude/CLAUDE.md
ln -sf ~/.dotfiles/home/.claude/settings.json ~/.claude/settings.json
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
  echo "$HOME/.dotfiles-private not cloned - skipping private config"
fi

# Claude Code personal skills. Keep ~/.claude/skills as a real directory so
# skills installed by other means are left alone, and symlink in each skill
# vendored under .dotfiles/home/.claude/skills/.
#
# Where each skill comes from (keep this the only place that says so):
#   vendored  home/.claude/skills/<name>/, pinned by .upstream, drift reported
#             by scripts/check_skill_updates.sh. Bump = re-copy + update commit=.
#   plugin    mattpocock-skills@claude-plugins-official, enabled in
#             home/.claude/settings.json; its skills resolve by bare name
#             (/grill-me, /tdd, ...). Never copy them into ~/.claude/skills:
#             a loose copy shadows the plugin and stops updating.
# Gotcha: `npx skills add <repo> --skill=<name>` with a non-interactive flag
# copies EVERY skill in the repo, not just <name>. Vendor by hand instead.
mkdir -p ~/.claude/skills
for skill in ~/.dotfiles/home/.claude/skills/*/; do
  [ -d "$skill" ] || continue
  link=~/.claude/skills/"$(basename "$skill")"
  # A real directory here (e.g. a skill installed by `npx skills add` before
  # it was vendored) would make ln -sfn drop the link *inside* it rather than
  # replace it. Stop and let the user decide which copy wins.
  if [ -d "$link" ] && [ ! -L "$link" ]; then
    warn "$link is a real directory, not a symlink; remove or move it first"
    continue
  fi
  ln -sfn "${skill%/}" "$link"
done

# Expose the same skills under ~/.agents/skills for tools that look there.
mkdir -p ~/.agents
rm -rf ~/.agents/skills
ln -s ~/.claude/skills ~/.agents/skills

# Directory links get an explicit target with -n: `ln -sf <dir> ~/.config/`
# would follow an existing ~/.config/<name> link on a re-run and drop a
# second link inside the repo directory instead of replacing it.
ln -sfn ~/.dotfiles/home/.config/ghostty ~/.config/ghostty

# fish, with its plugins vendored in the repo (see conf.d/plugins.fish). Any
# fish run before this install leaves a real ~/.config/fish (fish_variables
# at least), where ln -sfn would drop the link inside; let the user decide.
if [ -d ~/.config/fish ] && [ ! -L ~/.config/fish ]; then
  warn "$HOME/.config/fish is a real directory, not a symlink; move it aside (keep fish_variables if you want its universal variables) and re-run"
else
  ln -sfn ~/.dotfiles/home/.config/fish ~/.config/fish
fi
# Neovim, plugin-free (see its init.lua). Same real-directory guard as fish:
# nvim writes nothing into its config dir, but an older hand-made one may exist.
if [ -d ~/.config/nvim ] && [ ! -L ~/.config/nvim ]; then
  warn "$HOME/.config/nvim is a real directory, not a symlink; move it aside and re-run"
else
  ln -sfn ~/.dotfiles/home/.config/nvim ~/.config/nvim
fi

# fd's global ignore file; fish's FZF_FIND_FILE_COMMAND also passes it explicitly
ln -sfn ~/.dotfiles/home/.config/fd ~/.config/fd

mkdir -p ~/.local/{bin,local}
ln -sf ~/.dotfiles/home/.npmrc ~/.npmrc

ln -sfn ~/.dotfiles/home/.config/uv ~/.config/uv

# macOS only
if [ "$(uname)" = "Darwin" ]; then
  # IINA reads ~/.config/iina as its mpv config dir, incl. scripts/
  ln -sfn ~/.dotfiles/home/.config/iina ~/.config/iina

  # IINA lists its key-binding confs (Preferences > Key Bindings) from this
  # directory with the URL-based FileManager API, which refuses a symlinked
  # directory (fatal "Cannot get user config file!" at launch), and saves them
  # with an atomic write that replaces a symlinked file by a plain one. So the
  # repo file is the source and IINA gets a plain copy: installed when absent,
  # left alone when identical, and a warning when the two differ, since
  # either side may hold the newer edit and only you know which.
  iina_conf=~/.dotfiles/home/.config/iina/input_conf/my.conf
  iina_installed="$HOME/Library/Application Support/com.colliderli.iina/input_conf/my.conf"
  mkdir -p "$(dirname "$iina_installed")"
  if [ ! -e "$iina_installed" ]; then
    cp "$iina_conf" "$iina_installed"
  elif ! cmp -s "$iina_conf" "$iina_installed"; then
    warn "IINA key bindings differ between the repo and the installed copy:
       repo -> IINA: cp '$iina_conf' '$iina_installed'
       IINA -> repo: cp '$iina_installed' '$iina_conf'"
  fi

  mkdir -p ~/.colima/default
  ln -sf ~/.dotfiles/home/.colima/default/colima.yaml ~/.colima/default/colima.yaml

  ln -sfn ~/.dotfiles/home/.hammerspoon ~/.hammerspoon
  # Machine-private Hammerspoon settings (Chrome profiles, work URLs) stay out
  # of this repo and get linked in, the same way ~/.ssh/local_config does. The
  # link is git-ignored; init.lua simply requires "local_hammerspoon", since
  # Hammerspoon already searches ~/.hammerspoon/?.lua.

  # Login key remaps (caps lock -> ctrl, PC menu key -> right option)
  mkdir -p ~/Library/LaunchAgents
  keyremap_label=com.hovnatan.keyremap
  ln -sf ~/.dotfiles/home/Library/LaunchAgents/"$keyremap_label".plist ~/Library/LaunchAgents/
  launchctl bootout "gui/$(id -u)/$keyremap_label" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/"$keyremap_label".plist

  # Preview markup colors (magenta annotations for LLM screenshot review).
  # The setup script quits Preview, which declines with open documents, so
  # only run it when the defaults are absent and Preview is closed; run it
  # by hand to reset after picking another color in the markup toolbar.
  preview_markup=~/.dotfiles/scripts/macos/setup_preview_markup.sh
  if ! defaults read com.apple.Preview com.apple.AnnotationKit.strokeColor &> /dev/null; then
    if pgrep -xq Preview; then
      warn "Preview markup defaults not set and Preview is open; close it and run $preview_markup"
    else
      "$preview_markup" || warn "$preview_markup failed"
    fi
  fi

  # IINA starts every file paused by default ("Pause when opening a file").
  # Play on open instead. IINA reads this from UserDefaults at each file open,
  # so it takes effect without a restart; repo is the source, so re-running
  # resets a change made in Preferences > General.
  defaults write com.colliderli.iina pauseWhenOpen -bool false

  # Hunspell + en_US dictionary (brew ships no dictionaries)
  ~/.dotfiles/scripts/macos/setup_hunspell.sh || warn "setup_hunspell.sh failed"
fi

if [ "$failed" -ne 0 ]; then
  echo "Done, with warnings above" >&2
  exit 1
fi
echo "Done"
