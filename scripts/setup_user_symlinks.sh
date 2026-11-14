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

# tmux reads ~/.config/tmux/tmux.conf; ~/.tmux.conf, its home until 2026-11-05, goes
# so a machine is not left with a dead link. The file is linked rather than the
# directory, as ~/.config/tmux can be a real one. Where it is already a link into
# this repo the config is reached through it, and a link here would point at itself.
rm -rf ~/.tmux.conf
mkdir -p ~/.config/tmux
[ -L ~/.config/tmux ] || ln -sfn ~/.dotfiles/home/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf

[ -L ~/.zshrc ] && rm -f ~/.zshrc
if ! grep -qs '\.dotfiles/home/\.zshrc\.shared' ~/.zshrc; then
  cat <<EOT >>~/.zshrc
if [[ -f "\$HOME/.dotfiles/home/.zshrc.shared" ]]; then
  source "\$HOME/.dotfiles/home/.zshrc.shared"
fi
EOT
fi

if ! grep -qs '\.dotfiles/home/\.zprofile' ~/.zprofile; then
  cat <<EOT >>~/.zprofile
if [[ -f "\$HOME/.dotfiles/home/.zprofile" ]]; then
  source "\$HOME/.dotfiles/home/.zprofile"
fi
EOT
fi

# The shell-neutral environment (EDITOR, MAKEFLAGS, ~/.local/bin, ...) for
# every login shell: bash reads ~/.profile directly, zsh through .zprofile.
# POSIX sh, since dash and sh read ~/.profile too.
if ! grep -qs '\.dotfiles/home/\.profile\.shared' ~/.profile; then
  cat <<EOT >>~/.profile
if [ -f "\$HOME/.dotfiles/home/.profile.shared" ]; then
  . "\$HOME/.dotfiles/home/.profile.shared"
fi
EOT
fi

rm -rf ~/.vimrc
ln -s ~/.dotfiles/home/.vimrc ~/.vimrc

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
  cat <<EOT >>~/.gitconfig
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

# This repo's own git hooks (scripts/git-hooks/): pre-push runs
# scripts/check.sh on what is being pushed. Set in the repo's config, so it
# holds for every push from this clone, whatever directory started it.
git -C ~/.dotfiles config core.hooksPath scripts/git-hooks

# `git blame` here skips the bulk reformatting commits listed in
# .git-blame-ignore-revs (shfmt, fish_indent), so a line shows its last real
# change.
git -C ~/.dotfiles config blame.ignoreRevsFile .git-blame-ignore-revs

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

# Global agent instructions: one canonical file,
# home/AGENTS_global_instructions.md, installed under whatever name each tool
# reads. At user level Claude Code reads only ~/.claude/CLAUDE.md (since
# v2.1.277 it reads AGENTS.md in projects, never at user level); Codex reads
# ~/.codex/AGENTS.md. Add ~/.config/opencode/AGENTS.md if opencode is ever
# installed. The source is not named AGENTS.md: in a project an agent loads
# every AGENTS.md above the files it reads, so work under home/ got the same
# instructions a second time.
ln -sf ~/.dotfiles/home/AGENTS_global_instructions.md ~/.codex/AGENTS.md

mkdir -p ~/.claude
ln -sf ~/.dotfiles/home/AGENTS_global_instructions.md ~/.claude/CLAUDE.md
ln -sf ~/.dotfiles/home/.claude/settings.json ~/.claude/settings.json
ln -sf ~/.dotfiles/home/.claude/keybindings.json ~/.claude/keybindings.json
# Custom /theme presets (gruvbox-light, gruvbox-dark). Claude Code watches this
# directory, and "New custom theme..." in /theme writes here, so themes made
# there land in the repo too.
ln -sfn ~/.dotfiles/home/.claude/themes ~/.claude/themes
# settings.json names the theme "custom:gruvbox": gruvbox.json in there is a
# machine-local link to the light or the dark one, pointed at the end of this
# script (scripts/appearance.sh).

# Private companion repos, both OPTIONAL: a machine without a clone still
# installs cleanly, it just goes without what that clone carries.
#
#   ~/.dotfiles-private      personal: the hunspell word list, the grammar-drill bank
#   ~/.hov-dotfiles-private  work: claude-worklog (the work log routine),
#                            anything naming an internal document or host
#
# Each mirrors $HOME under home/, like this repo; every home/.config/<dir>
# in either is linked whole into ~/.config, and in the work repo every other
# file is linked to its own path (link_private_files).
link_private_config() {
  local repo=$1 d target
  mkdir -p ~/.config
  for d in "$repo"/home/.config/*/; do
    [ -d "$d" ] || continue
    target=~/.config/"$(basename "$d")"
    # ln -sfn would drop the link INSIDE a real directory of the same name
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      warn "$target is a real directory; move its contents into $repo and re-run"
      continue
    fi
    ln -sfn "${d%/}" "$target"
  done
}

# Files elsewhere under home/ are linked one by one to the same path under
# $HOME, creating parent directories, e.g. a project's .claude settings:
#   <repo>/home/<dir>/.claude/settings.local.json -> ~/<dir>/.claude/settings.local.json
# A real file in the way is reported, never replaced: it may hold changes
# made since the copy in the repo.
link_private_files() {
  local repo=$1 f target
  while IFS= read -r -d '' f; do
    target=~/"${f#"$repo"/home/}"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      warn "$target is a real file; merge it into $f, delete it and re-run"
      continue
    fi
    mkdir -p "$(dirname "$target")"
    ln -sfn "$f" "$target"
  done < <(find "$repo"/home -path "$repo/home/.config" -prune -o -type f -print0)
}

# Until 2026-09-28 the work repo was cloned at ~/.dotfiles-private. Left
# there, its config would be linked as if personal and the personal repo
# could not be cloned; moving it relinks everything on the re-run.
if git -C ~/.dotfiles-private remote get-url origin 2>/dev/null | grep -q '/hov-dotfiles-private'; then
  warn "$HOME/.dotfiles-private is the work repo; mv ~/.dotfiles-private ~/.hov-dotfiles-private, then re-run"
elif [ -d ~/.dotfiles-private/home ]; then
  # Hunspell personal word list (technical terms). The name matches the en_US
  # dictionary so hunspell finds it by default; WORDLIST in .profile.shared
  # points here too, covering other locales. Interactive saves write through
  # the link.
  ln -sf ~/.dotfiles-private/home/.hunspell_en_US ~/.hunspell_en_US

  # The same list is nvim's spellfile (core/options.lua), so zg and a
  # hunspell save add to one list. nvim wants the name to end in
  # .utf-8.add, hence a second link rather than ~/.hunspell_en_US itself;
  # its compiled .spl lands next to this link, outside every repo. A real
  # file here holds words zg added before the link - merge them first.
  nvim_spell=~/.local/share/nvim/spell/en.utf-8.add
  if [ -e "$nvim_spell" ] && [ ! -L "$nvim_spell" ]; then
    warn "$nvim_spell is a real file; append its words to ~/.dotfiles-private/home/.hunspell_en_US, delete it and re-run"
  else
    mkdir -p "$(dirname "$nvim_spell")"
    ln -sf ~/.dotfiles-private/home/.hunspell_en_US "$nvim_spell"
  fi

  link_private_config ~/.dotfiles-private
else
  # The word list used to live in this repo; drop the link left dangling by
  # the move rather than let a hunspell save recreate it here untracked.
  if [ -L ~/.hunspell_en_US ] && [ ! -e ~/.hunspell_en_US ]; then
    rm ~/.hunspell_en_US
  fi
  echo "$HOME/.dotfiles-private not cloned - hunspell and nvim have no personal word list"
fi

if [ -d ~/.hov-dotfiles-private/home ]; then
  link_private_config ~/.hov-dotfiles-private
  link_private_files ~/.hov-dotfiles-private
else
  echo "$HOME/.hov-dotfiles-private not cloned - no work log routine"
fi

# Claude Code personal skills. Keep ~/.claude/skills as a real directory so
# skills installed by other means are left alone, and symlink in each skill
# vendored under .dotfiles/home/.claude/skills/.
#
# Where each skill comes from (keep this the only place that says so):
#   vendored  home/.claude/skills/<name>/, pinned by .upstream, drift reported
#             by scripts/check_skill_updates.sh. Bump = re-copy + update commit=.
#   plugin    mattpocock-skills@mattpocock, from the author's own marketplace
#             (mattpocock/skills), both declared in home/.claude/settings.json;
#             its skills resolve by bare name (/grill-me, /tdd, /retro, ...).
#             Not @claude-plugins-official: that catalog's pin lagged upstream
#             by weeks. Never copy them into ~/.claude/skills: a loose copy
#             shadows the plugin and stops updating.
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
# A skill removed from the repo leaves its link dangling (the /label skill,
# 2026-10-23): drop the links into home/.claude/skills that point at nothing.
# Only those -- a link elsewhere, or a real directory, is not ours to judge.
for link in ~/.claude/skills/*; do
  [ -L "$link" ] && [ ! -e "$link" ] || continue
  case $(readlink "$link") in
    "$HOME"/.dotfiles/home/.claude/skills/*) rm "$link" && echo "removed $link (its skill left the repo)" ;;
  esac
done

# Expose the same skills under ~/.agents/skills for tools that look there.
mkdir -p ~/.agents
rm -rf ~/.agents/skills
ln -s ~/.claude/skills ~/.agents/skills

# Directory links get an explicit target with -n: `ln -sf <dir> ~/.config/`
# would follow an existing ~/.config/<name> link on a re-run and drop a
# second link inside the repo directory instead of replacing it.
ln -sfn ~/.dotfiles/home/.config/ghostty ~/.config/ghostty

# fish. Any fish run before this install leaves a real ~/.config/fish
# (fish_variables at least), where ln -sfn would drop the link inside; let the
# user decide.
if [ -d ~/.config/fish ] && [ ! -L ~/.config/fish ]; then
  warn "$HOME/.config/fish is a real directory, not a symlink; move it aside (keep fish_variables if you want its universal variables) and re-run"
else
  ln -sfn ~/.dotfiles/home/.config/fish ~/.config/fish
fi

# fish plugins: bring fisher's installed set in line with the pinned
# fish_plugins (see home/.config/fish/conf.d/plugins.fish). Gated on the two
# lists differing, compared sorted since fisher appends a re-pinned plugin at
# the end of its list, so a dotup with nothing changed downloads nothing.
#   fresh machine   fisher missing -> source fisher.fish at its pinned commit,
#                   then `fisher update` installs everything, fisher included
#   pin changed     `fisher update` swaps the old commit for the new one
# fisher prints download failures but still exits 0, so the lists are
# compared again afterwards. No fish on this machine: nothing to do.
if command -v fish >/dev/null; then
  fish_plugins=~/.dotfiles/home/.config/fish/fish_plugins
  fisher_plugins_differ() {
    # shellcheck disable=SC2016 # $_fisher_plugins is fish's, expanded by fish
    [ "$(tr '[:upper:]' '[:lower:]' <"$fish_plugins" | sort)" != \
      "$(fish -c 'string join \n -- $_fisher_plugins' 2>/dev/null | sort)" ]
  }
  if fisher_plugins_differ; then
    fisher_rev=$(sed -n 's|^jorgebucaran/fisher@||p' "$fish_plugins")
    if [ -z "$fisher_rev" ]; then
      warn "$fish_plugins has no jorgebucaran/fisher@<sha> line; add it back so fisher can be bootstrapped"
    else
      echo "fish plugins: syncing with $fish_plugins"
      fish -c "functions -q fisher; or curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/$fisher_rev/functions/fisher.fish | source; and fisher update"
      fisher_plugins_differ && warn "fisher's installed plugins still differ from $fish_plugins; see the fisher output above, fix, and re-run"
    fi
  fi
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

# glow (nix/flake.nix) reads glow.yml from ~/Library/Preferences/glow on macOS
# and ~/.config/glow elsewhere. The file is linked, not the directory: glow
# writes a default glow.yml there on first run, and that generated copy holds
# nothing to keep, so -f replaces it.
if [ "$(uname)" = "Darwin" ]; then
  glow_dir="$HOME/Library/Preferences/glow"
else
  glow_dir=~/.config/glow
fi
mkdir -p "$glow_dir"
ln -sf ~/.dotfiles/home/.config/glow/glow.yml "$glow_dir"/glow.yml

# fd's global ignore file; fish's FZF_FIND_FILE_COMMAND also passes it explicitly
ln -sfn ~/.dotfiles/home/.config/fd ~/.config/fd
# ripgrep's defaults; RIPGREP_CONFIG_PATH in home/.profile.shared points here
ln -sfn ~/.dotfiles/home/.config/ripgrep ~/.config/ripgrep
# ruff's user config, used only where a project has no ruff settings of its
# own; ~/.config/ruff on macOS too (checked with ruff 0.15.7 and 0.16.8)
ln -sfn ~/.dotfiles/home/.config/ruff ~/.config/ruff
# markdownlint-cli2's user config, used only where a project has none of its
# own; the tool reads no user-level file by itself, so the global agent
# instructions pass it with --config
ln -sfn ~/.dotfiles/home/.config/markdownlint ~/.config/markdownlint

mkdir -p ~/.local/{bin,local}
ln -sf ~/.dotfiles/home/.npmrc ~/.npmrc

ln -sfn ~/.dotfiles/home/.config/uv ~/.config/uv

# docker's zsh completion, where home/.zshrc.shared's fpath looks for it.
# Regenerated on every run, so it follows the docker installed (apt/Aptfile
# on Ubuntu, Docker Desktop on macOS); written beside and renamed in, so a
# docker that fails leaves the old file. No docker on this machine: nothing
# to do.
if command -v docker >/dev/null; then
  mkdir -p ~/.docker/completions
  if docker completion zsh >~/.docker/completions/_docker.new; then
    mv ~/.docker/completions/_docker.new ~/.docker/completions/_docker
  else
    rm -f ~/.docker/completions/_docker.new
    warn "'docker completion zsh' failed (message above); $HOME/.docker/completions/_docker left as it was"
  fi
fi

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

  # colima's config used to live in this repo (removed 2026-10-07, colima
  # unused); drop the link left dangling rather than let colima trip on it.
  if [ -L ~/.colima/default/colima.yaml ] && [ ! -e ~/.colima/default/colima.yaml ]; then
    rm ~/.colima/default/colima.yaml
  fi

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

  # D-Bus session bus, over which scripts/appearance.sh recolours the zathura
  # windows that are open (scripts/macos/dbus_session.sh). Started only if
  # it does not run: zathura joins the bus once, at its start, so a restart
  # would cut every open window off from it.
  dbus_label=com.hovnatan.dbus-session
  ln -sf ~/.dotfiles/home/Library/LaunchAgents/"$dbus_label".plist ~/Library/LaunchAgents/
  if [ ! -x ~/.nix-profile/bin/dbus-daemon ]; then
    warn "dbus is not installed yet, so open zathura windows will not follow light/dark:
       nix profile upgrade nix (dotup does it after this script), then re-run this script"
  elif ! launchctl print "gui/$(id -u)/$dbus_label" 2>/dev/null | grep -q 'state = running'; then
    launchctl bootout "gui/$(id -u)/$dbus_label" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/"$dbus_label".plist
    for _ in $(seq 50); do
      [ -S ~/.cache/bus ] && break
      sleep 0.1
    done
    [ -S ~/.cache/bus ] || warn "the D-Bus session bus did not come up at ~/.cache/bus; see the newest ~/.dotfiles/.logs/*_dbus_session/events.log"
  fi

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

  # Default tracks: English audio and English subtitles (Preferences > Video/Audio
  # and > Subtitles, "Preferred language"). IINA hands these to mpv as alang/slang,
  # and mpv's prefix match lets "en" pick tracks tagged en-US and an external
  # "<name>.en.srt". E.g. a dub-first mkv (ru audio flagged default, en second)
  # opens on the en audio with en subs; mpv's default subs-with-matching-audio=yes
  # keeps the subs on although the audio is English too.
  defaults write com.colliderli.iina audioLanguage -string en
  defaults write com.colliderli.iina subLang -string en

  # Keyboard navigation (System Settings > Keyboard): Tab moves focus to
  # every button in a dialog and Space presses it, not only Return (default
  # button) and Esc (Cancel). E.g. a three-button dialog: Tab, Tab, Space
  # reaches the third button without the mouse. Apps launched afterwards
  # pick it up; restart the ones already running.
  defaults write -g AppleKeyboardUIMode -int 2

  # Ctrl+Return is Claude Code's "send queued prompt now" (chat:sendNow), but
  # macOS binds it system-wide to "Show contextual menu" (symbolic hotkey 159,
  # System Settings > Keyboard > Keyboard Shortcuts > Keyboard), so the key
  # opened the terminal's context menu and never reached the program. Disable
  # that shortcut; parameters keep the stock key (65535 = no char, 36 = Return,
  # 262144 = ctrl) so re-enabling it in System Settings restores it as it was.
  # activateSettings applies it to the running session without a re-login.
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 159 \
    '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>36</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>'
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u \
    || warn "activateSettings failed; log out and back in for the Ctrl+Return shortcut change"

  # iTerm2's profile used to live in this repo (removed 2026-11-10, Ghostty
  # only); drop the link left dangling. The com.googlecode.iterm2 defaults it
  # wrote stay until iTerm2 itself is uninstalled.
  iterm_profile="$HOME/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json"
  if [ -L "$iterm_profile" ] && [ ! -e "$iterm_profile" ]; then
    rm "$iterm_profile"
  fi

  # ~/Applications/Zathura.app: Finder/"Open With" front end for the Nix
  # zathura (the script says why not homebrew-zathura's). Rebuilt each run,
  # about a second, so the app follows the script.
  ~/.dotfiles/scripts/macos/build_zathura_app.sh >/dev/null \
    || warn "Zathura.app build failed (scripts/macos/build_zathura_app.sh)"

fi

# Light or dark, for Claude Code's theme and zathura (scripts/appearance.sh).
# A Mac is asked for its appearance, and Hammerspoon keeps the links in step
# from then on (home/.hammerspoon/appearance.lua). Linux cannot be asked, so
# the links are made once, dark; from then on they follow the terminal
# attached to tmux (home/.config/tmux/tmux.conf), or `scripts/appearance.sh light`.
if [ "$(uname)" = "Darwin" ]; then
  ~/.dotfiles/scripts/appearance.sh >/dev/null || warn "scripts/appearance.sh failed (message above)"
elif [ ! -L ~/.claude/themes/gruvbox.json ] || [ ! -L ~/.config/zathura/theme ]; then
  ~/.dotfiles/scripts/appearance.sh dark >/dev/null || warn "scripts/appearance.sh dark failed (message above)"
fi

if [ "$failed" -ne 0 ]; then
  echo "Done, with warnings above" >&2
  exit 1
fi
echo "Done"
