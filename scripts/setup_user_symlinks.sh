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

cd ~ || exit 1

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/home/.tmux.conf ~/.tmux.conf

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

# The shell-neutral environment (EDITOR, MAKEFLAGS, ~/.local/bin, ...) for
# every login shell: bash reads ~/.profile directly, zsh through .zprofile.
# POSIX sh, since dash and sh read ~/.profile too.
if ! grep -qs '\.dotfiles/home/\.profile\.shared' ~/.profile; then
cat <<EOT >> ~/.profile
if [ -f "\$HOME/.dotfiles/home/.profile.shared" ]; then
  . "\$HOME/.dotfiles/home/.profile.shared"
fi
EOT
fi

mkdir -p ~/.vimundo/
rm -rf ~/.vimrc
ln -s ~/.dotfiles/home/.vimrc ~/.vimrc

# Hunspell personal word list (technical terms). The name matches the en_US
# dictionary so hunspell finds it by default; WORDLIST in .profile.shared points
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
# Custom /theme presets (gruvbox-light, gruvbox-dark). Claude Code watches this
# directory, and "New custom theme..." in /theme writes here, so themes made
# there land in the repo too.
ln -sfn ~/.dotfiles/home/.claude/themes ~/.claude/themes

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
# Neovim (see its init.lua). Same real-directory guard as fish: an older
# hand-made config dir may exist. vim.pack writes nvim-pack-lock.json into the
# config dir, which through this link lands in the repo, as intended.
if [ -d ~/.config/nvim ] && [ ! -L ~/.config/nvim ]; then
  warn "$HOME/.config/nvim is a real directory, not a symlink; move it aside and re-run"
else
  ln -sfn ~/.dotfiles/home/.config/nvim ~/.config/nvim
fi

# zathura (macOS, from nix/flake.nix). Same guard: an older install left a real
# ~/.config/zathura holding a link to the since-renamed zathura_light/zathurarc.
if [ -d ~/.config/zathura ] && [ ! -L ~/.config/zathura ]; then
  warn "$HOME/.config/zathura is a real directory, not a symlink; move it aside and re-run"
else
  ln -sfn ~/.dotfiles/home/.config/zathura ~/.config/zathura
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

  # Preview markup colors (magenta annotations for LLM screenshot review) are
  # not applied here: the script has to quit Preview, which declines with
  # open documents, and a warning on every run whenever Preview was open cost
  # more than the colors are worth. Run it by hand when wanted:
  #   ~/.dotfiles/scripts/macos/setup_preview_markup.sh

  # IINA starts every file paused by default ("Pause when opening a file").
  # Play on open instead. IINA reads this from UserDefaults at each file open,
  # so it takes effect without a restart; repo is the source, so re-running
  # resets a change made in Preferences > General.
  defaults write com.colliderli.iina pauseWhenOpen -bool false

  # iTerm2 set up to match home/.config/ghostty/config. The profile is a
  # Dynamic Profile (JSON, no comments possible, so the mapping lives here);
  # iTerm2 watches the folder, so edits apply to new sessions without a
  # restart. The globals below take effect on the next iTerm2 launch.
  #   theme light:/dark:Gruvbox    -> separate Light/Dark colours, values
  #                                   copied from Ghostty's bundled theme files
  #   font SF Mono 15, thicken     -> Menlo 14, thin strokes never. iTerm2
  #                                   cannot reproduce Ghostty's thickening
  #                                   (it rasterizes every glyph as white on
  #                                   black with font smoothing, so dark text
  #                                   gets the heavy dilation too); SF Mono
  #                                   Regular/Medium and Monaco 12-15 were
  #                                   tried, Menlo's heavier strokes won
  #   fullscreen = true            -> Window Type 4 (native fullscreen;
  #                                   5 docks to the bottom edge)
  #   command $SHELL -l -> fish    -> same chain via /bin/sh, since iTerm2
  #                                   does not expand $SHELL itself
  #   shell-integration = fish     -> none needed: fish 4 emits OSC 7 and
  #                                   OSC 133 itself, and iTerm2 reads both;
  #                                   its blue prompt-mark triangles are off,
  #                                   as Ghostty draws none
  #   confirm-close-surface=false  -> never prompt on close or quit
  #   copy-on-select = clipboard   -> CopySelection
  #   super+j / super+k            -> cmd+j / cmd+k previous / next tab
  #   titlebar transparent         -> Minimal theme (titlebar in bg colour)
  # mouse-hide-while-typing has no iTerm2 equivalent.
  iterm_profiles="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$iterm_profiles"
  ln -sf ~/.dotfiles/"home/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json" "$iterm_profiles/"
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string 45FCCF80-D41B-400A-A797-004E6F3CAD2A
  defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5
  defaults write com.googlecode.iterm2 UseLionStyleFullscreen -bool true
  defaults write com.googlecode.iterm2 PromptOnQuit -bool false
  defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
  defaults write com.googlecode.iterm2 CopySelection -bool true
  # OSC 52 clipboard writes (remote tmux/nvim/Claude Code copying to the Mac
  # clipboard), allowed as Ghostty's clipboard-write = allow does; iTerm2
  # denies them by default. Reads stay at iTerm2's ask-each-time, matching
  # Ghostty's clipboard-read = ask.
  defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
  # Minimal theme's tab bar height in points (default 38, 22 = compact
  # theme); 28 sits nearer Ghostty's native macOS tab bar. Read at launch.
  defaults write com.googlecode.iterm2 CompactMinimalTabBarHeight -float 28
  # Bell -> dock bounce while iTerm2 is in the background, as Ghostty does.
  # The desktop notification itself comes from OSC 1337 (see the fish/zsh
  # long-command hooks and ~/.claude/notify-stop.sh); the profile turns on
  # notifications but not the per-bell one, which would post it twice.
  defaults write com.googlecode.iterm2 BounceOnInactiveBell -bool true
  # Key "<char>-<modifiers>-<keycode>": 0x100000 is cmd, keycodes 38 = j,
  # 40 = k. Action 2 is previous tab, 0 next tab. -dict-add keeps the other
  # entries (shift+enter -> \n, set in the iTerm2 UI).
  iterm_key() { # $1 char, $2 keycode, $3 action
    defaults write com.googlecode.iterm2 GlobalKeyMap -dict-add \
      "$(printf '0x%x-0x100000-0x%x' "'$1" "$2")" \
      "<dict><key>Action</key><integer>$3</integer><key>Text</key><string></string><key>Version</key><integer>1</integer><key>Keycode</key><integer>$2</integer><key>Modifiers</key><integer>1048576</integer></dict>"
  }
  iterm_key j 38 2
  iterm_key k 40 0

  # ~/Applications/Zathura.app: Finder/"Open With" front end for the Nix
  # zathura (the script says why not homebrew-zathura's). Rebuilt each run,
  # about a second, so the app follows the script.
  ~/.dotfiles/scripts/macos/build_zathura_app.sh >/dev/null \
    || warn "Zathura.app build failed (scripts/macos/build_zathura_app.sh)"

fi

if [ "$failed" -ne 0 ]; then
  echo "Done, with warnings above" >&2
  exit 1
fi
echo "Done"
