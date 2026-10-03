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
#   ~/.dotfiles-private      personal: the hunspell word list
#   ~/.hov-dotfiles-private  work: claude-worklog (the work log routine),
#                            anything naming an internal document or host
#
# Each mirrors $HOME under home/, like this repo; every home/.config/<dir>
# in either is linked whole into ~/.config.
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
    for _ in $(seq 50); do [ -S ~/.cache/bus ] && break; sleep 0.1; done
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

  # Keyboard navigation (System Settings > Keyboard): Tab moves focus to
  # every button in a dialog and Space presses it, not only Return (default
  # button) and Esc (Cancel). E.g. iTerm2's Paste Image dialog: cmd+v, Tab,
  # Space reaches "Paste Base64-Encoded Contents" (pasteimg on a remote).
  # Apps launched afterwards pick it up; restart the ones already running.
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

  # iTerm2 set up to match home/.config/ghostty/config. The profile is a
  # Dynamic Profile (JSON, no comments possible, so the mapping lives here);
  # iTerm2 watches the folder, so edits apply to new sessions without a
  # restart. The globals below take effect on the next iTerm2 launch.
  #   theme light:/dark:Gruvbox    -> separate Light/Dark colours, values
  #                                   copied from Ghostty's bundled theme files
  #   font SF Mono 15, thicken     -> Menlo 14, thin strokes never: the
  #                                   same face and size as the VS Code
  #                                   editor (its default). iTerm2 cannot
  #                                   reproduce Ghostty's thickening (it
  #                                   rasterizes every glyph white on black
  #                                   with font smoothing, so dark text gets
  #                                   the heavy dilation too). Tried and
  #                                   dropped: SF Mono Regular/Medium, Monaco
  #                                   12-15, JetBrains Mono, Monaspace Neon,
  #                                   Intel One Mono, Cascadia Code, Commit
  #                                   Mono 400/450/500 (86b41fb5 has the 500
  #                                   build)
  #   built-in Nerd Font icons     -> Non-ASCII font Symbols Nerd Font
  #                                   Mono (SymbolsNFM, Brewfile cask
  #                                   font-symbols-only-nerd-font); Menlo
  #                                   has none, so icons drew as ? boxes
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
  #   macos-option-as-alt (unset)  -> both Option keys Esc+ (2): unset means
  #                                   Alt on U.S. layouts, so option-p is
  #                                   alt-p, not "pi" (Normal, 0, types that)
  #   super+j / super+k            -> cmd+j / cmd+k previous / next tab
  #   titlebar transparent         -> Minimal theme (titlebar in bg colour)
  # mouse-hide-while-typing has no iTerm2 equivalent.
  iterm_profiles="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$iterm_profiles"
  # iTerm2 reloads dynamic profiles when this folder changes, and an edit to
  # the linked file leaves the folder alone: re-running this ln -sf (dotup) is
  # what makes a running iTerm2 pick the edit up.
  ln -sf ~/.dotfiles/"home/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json" "$iterm_profiles/"
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string 45FCCF80-D41B-400A-A797-004E6F3CAD2A
  defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5
  defaults write com.googlecode.iterm2 UseLionStyleFullscreen -bool true
  defaults write com.googlecode.iterm2 PromptOnQuit -bool false
  defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
  defaults write com.googlecode.iterm2 CopySelection -bool true
  # 24-bit colours from programs in sRGB, like the profile colours (and
  # Ghostty's window-colorspace = srgb). iTerm2 reads them as Display P3 by
  # default, so nvim's gruvbox bg #fbf1c7 drew visibly off from the same
  # #fbf1c7 of the profile background around it.
  defaults write com.googlecode.iterm2 P3 -bool false
  # No blue new-output dot and no activity spinner on background tabs: the
  # Claude Code status line redraws its clock every minute (refreshInterval
  # 60), so every idle Claude tab got the dot and a spinner blip, and
  # neither meant anything. The Stop hook's bell still marks a finished
  # turn with the tab's bell icon, which is all Ghostty shows too.
  defaults write com.googlecode.iterm2 ShowNewOutputIndicator -bool false
  defaults write com.googlecode.iterm2 HideActivityIndicator -bool true
  # New tabs open right after the current one, as Ghostty's default
  # window-new-tab-position = current does; iTerm2 appends them at the end.
  defaults write com.googlecode.iterm2 AddNewTabAtEndOfTabs -bool false
  # Tab bar shown for a one-tab window too (Appearance > Tabs > Show tab bar
  # even when there is only one tab). iTerm2 hides it by default, so the
  # terminal lost a row of height the moment a second tab opened.
  defaults write com.googlecode.iterm2 HideTab -bool false
  # Long tab titles always lose their end, never their start, so the host tag
  # that leads them ("(mbp) ~/.dotfiles", iterm2_report_host.fish) stays
  # visible. Smart truncation (the default) cuts the start instead whenever a
  # window's titles share it: six tabs titled "(mbp) START ... END" all read
  # "...well past the tab width END". No setting always cuts the start, so a
  # tag at the end would be lost whenever titles differ early.
  defaults write com.googlecode.iterm2 TabTitlesUseSmartTruncation -bool false
  # OSC 52 clipboard writes (remote tmux/nvim/Claude Code copying to the Mac
  # clipboard), allowed as Ghostty's clipboard-write = allow does; iTerm2
  # denies them by default. Reads stay at iTerm2's ask-each-time, matching
  # Ghostty's clipboard-read = ask.
  defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
  # Minimal theme's tab bar height in points (default 38, 22 = compact
  # theme); 28 sits nearer Ghostty's native macOS tab bar. Read at launch.
  defaults write com.googlecode.iterm2 CompactMinimalTabBarHeight -float 28
  # Tab titles at the profile's font size (dotfiles.json "Menlo-Regular 14"),
  # not the smaller default. Only the size can be set: the face stays the
  # system font, and it does not follow cmd+/- zoom.
  defaults write com.googlecode.iterm2 UseCustomTabBarFontSize -bool true
  defaults write com.googlecode.iterm2 CustomTabBarFontSize -float 14
  # Bell -> dock bounce while iTerm2 is in the background, as Ghostty does.
  # The fish/zsh long-command hooks and Claude Code (preferredNotifChannel
  # terminal_bell) ring only the bell, no OSC notification of their own.
  # The profile's Send Bell Alert turns a bell into a macOS notification
  # instead, but Suppress Alerts in Active Session keeps it to other tabs:
  # macOS never bounces the dock for the frontmost app, so while iTerm2 is
  # in front the banner is the only signal that a background tab rang. Manual step per machine:
  # System Settings > Notifications > iTerm2 > Persistent, so a banner
  # waits until dismissed (the style lives in an undocumented com.apple.ncprefs
  # bitfield, not scripted here). A banner closes once its tab gets focus
  # (home/.hammerspoon/iterm2_bell_banners.lua); alt+0 clears them all
  # (home/.hammerspoon/clear_notifications.lua).
  defaults write com.googlecode.iterm2 BounceOnInactiveBell -bool true
  # Launch opens the default window arrangement (General > Startup > Open
  # Default Window Arrangement). The arrangement itself is per machine,
  # saved by hand: Window > Save Window Arrangement, then Settings >
  # Arrangements > Set Default. It keeps each window as it was saved, the
  # window title included, so re-save it after changing the profile's
  # Custom Window Title (iterm2_report_host.fish).
  defaults write com.googlecode.iterm2 OpenArrangementAtStartup -bool true
  # Tip of the Day, at most one a day after launch. Without the permission
  # key iTerm2 first asks whether to show tips at all; NoSyncTipsDisabled
  # turns them off outright. Tips already seen are kept in
  # NoSyncTipsToNotShow, left alone so they do not repeat.
  defaults write com.googlecode.iterm2 NoSyncPermissionToShowTip -bool true
  defaults write com.googlecode.iterm2 NoSyncTipsDisabled -bool false
  # Terminal modes a remote tmux/nvim/Claude Code switches on and never
  # switches off when the ssh connection drops (sleep, network change).
  # Back at the local prompt they turn into junk input: focus -> ^[[I/^[[O
  # on every window switch, mouse -> ^[[<0;45;12M on clicks, DEC 2048 ->
  # size reports on resize, bracketed paste -> ^[[200~ in a plain sh.
  # iTerm2 notices when the host changes back and asks "Looks like focus
  # reporting was left on ... Turn it off?", one banner per mode.
  #
  # The banners are left to ask. From 2026-09-27 to 09-30 these keys were
  # true, the banner's "Always", which resets the modes silently; they are
  # deleted from machines that got that. iTerm2 also takes a host for
  # changed while a tab is still attached to a remote tmux (what makes it
  # do so is not known yet), and tmux asks for these modes once, at attach:
  # a silent reset there leaves it without them for the rest of the attach.
  # With focus reports gone, home/.claude/ntfy-stop.sh saw nobody looking
  # and pushed a turn that was being watched (2026-09-30), and nothing on
  # screen said why. Answer No while attached, Yes back at a local prompt
  # after a dropped connection; "Always" sets the key true again.
  #   unset: the banner asks   true: reset silently   false: never reset,
  #   never ask (checked for focus reporting in iTerm2 3.7.3)
  for mode in FocusReporting MouseReporting BracketedPaste DEC2048; do
    defaults delete com.googlecode.iterm2 "NoSyncTurnOff${mode}OnHostChange" 2>/dev/null
  done
  # Same banner family for the title: a remote prompt/tmux/nvim retitles the
  # tab and the title outlives the ssh session. true restores the pre-ssh
  # tab and window title silently instead of asking.
  defaults write com.googlecode.iterm2 NoSyncRestoreIconAndWindowNameOnHostChange -bool true
  # No restore on relaunch or after a restart: a launch opens one fresh
  # default window, as Ghostty does here. iTerm2 has two restore paths and
  # both must go, or a restart with macOS's "Reopen windows when logging
  # back in" ticked still brings back every tab with "Session Contents
  # Restored" printed under its old scrollback:
  #
  #   quit / restart --> iTerm2's own SQLite store  --> restored at launch
  #                      (UseRestorableStateController)  unconditionally
  #                  --> macOS saved window state   --> restored unless
  #                      (NSPersistentUIManager)         ignored per app
  #
  # Advanced settings are read from the capitalized key (UI name
  # runJobsInServers -> key RunJobsInServers); a lowercase key is ignored.
  # All four are read at launch:
  #   RunJobsInServers false             -> shells no longer run in
  #                                         iTermServer daemons that outlive
  #                                         a quit and reattach on relaunch
  #   UseRestorableStateController false -> no SQLite store; it saves on a
  #                                         restart whatever the per-app
  #                                         setting below says. iTerm2 also
  #                                         mirrors this into
  #                                         NoSyncIgnoreSystemWindowRestoration
  #                                         at every launch
  #   ApplePersistenceIgnoreState true   -> macOS skips iTerm2's saved window
  #                                         state at launch, restart included
  #   NSQuitAlwaysKeepsWindows false     -> per-app "Close windows when
  #                                         quitting", so a plain quit saves
  #                                         nothing either
  defaults write com.googlecode.iterm2 RunJobsInServers -bool false
  defaults write com.googlecode.iterm2 UseRestorableStateController -bool false
  defaults write com.googlecode.iterm2 ApplePersistenceIgnoreState -bool true
  defaults write com.googlecode.iterm2 NSQuitAlwaysKeepsWindows -bool false
  # Clicked links open in the system browser, as in Ghostty. Without a
  # plugin installed, iTerm2 3.6+ asks "Plugin Required ... download the
  # Browser Plugin" (Download / Use System Browser / Cancel) on every click.
  # The pair below is what ticking "Remember my choice" and picking "Use
  # System Browser" (button 1) writes; the bool alone still showed the
  # dialog. NoSyncOpenLinksInApp is Advanced > Warnings "Open links using
  # the in-app browser?" (unset = ask each time).
  defaults write com.googlecode.iterm2 NoSyncOpenLinksInApp -bool false
  defaults write com.googlecode.iterm2 NoSyncBrowserUpsell -bool true
  defaults write com.googlecode.iterm2 NoSyncBrowserUpsell_selection -int 1
  # Key "<char>-<modifiers>-<keycode>": the char is what the key types with
  # shift applied and option ignored (cmd+option+j -> "j"), modifiers
  # 0x100000 cmd, 0x80000 option; keycodes 38 = j, 40 = k. Actions: 0 next
  # tab, 2 previous tab, 33 move tab left, 34 move tab right. The bindings
  # replace the menu items on the same keys (cmd+j Jump to Selection, cmd+k
  # Clear Buffer, cmd+option+j Script Console, cmd+option+k Clear Instant
  # Replay). Not cmd+shift+j/k: Homerow (Brewfile) holds cmd+shift+k (and
  # its scroll mode cmd+shift+j) as system-wide hotkeys, so iTerm2 never
  # saw them, even with iTerm2 on Homerow's ignore list. -dict-add keeps
  # the other entries (shift+enter -> \n, set in the iTerm2 UI).
  iterm_key() { # $1 char, $2 keycode, $3 modifiers, $4 action
    defaults write com.googlecode.iterm2 GlobalKeyMap -dict-add \
      "$(printf '0x%x-0x%x-0x%x' "'$1" "$3" "$2")" \
      "<dict><key>Action</key><integer>$4</integer><key>Text</key><string></string><key>Version</key><integer>1</integer><key>Keycode</key><integer>$2</integer><key>Modifiers</key><integer>$(($3))</integer></dict>"
  }
  iterm_key j 38 0x100000 2  # cmd+j: previous tab
  iterm_key k 40 0x100000 0  # cmd+k: next tab
  iterm_key j 38 0x180000 33 # cmd+option+j: move tab left
  iterm_key k 40 0x180000 34 # cmd+option+k: move tab right
  # shift+pageup / shift+pagedown: Scroll One Page Up / Down (actions 9 / 8),
  # the keys the Ctrl-U / Ctrl-D rewrites send on the main screen
  # (home/.hammerspoon/iterm2_keys.lua). They are in iTerm2's
  # DefaultGlobalKeyMap.plist, but a GlobalKeyMap in the prefs replaces that
  # whole file, so they are pinned here, in the plist's own form (no
  # keycode: 0xf72c / 0xf72d are NSPageUp/DownFunctionKey, 0x20000 shift).
  defaults write com.googlecode.iterm2 GlobalKeyMap -dict-add 0xf72c-0x20000 \
    "<dict><key>Action</key><integer>9</integer><key>Text</key><string></string></dict>"
  defaults write com.googlecode.iterm2 GlobalKeyMap -dict-add 0xf72d-0x20000 \
    "<dict><key>Action</key><integer>8</integer><key>Text</key><string></string></dict>"

  # ~/Applications/Zathura.app: Finder/"Open With" front end for the Nix
  # zathura (the script says why not homebrew-zathura's). Rebuilt each run,
  # about a second, so the app follows the script.
  ~/.dotfiles/scripts/macos/build_zathura_app.sh >/dev/null \
    || warn "Zathura.app build failed (scripts/macos/build_zathura_app.sh)"

  # Dark Reader for Chrome, built from source at the commit pinned in the
  # script, into ~/.local/share/dark-reader/chrome-mv3 (loaded in Chrome by
  # hand, once; the script says how). One line when that pin is already
  # built. Its output is shown: after a build it says what to do in Chrome.
  ~/.dotfiles/scripts/macos/build_dark_reader.sh \
    || warn "Dark Reader build failed (scripts/macos/build_dark_reader.sh)"

fi

# Light or dark, for Claude Code's theme and zathura (scripts/appearance.sh).
# A Mac is asked for its appearance, and Hammerspoon keeps the links in step
# from then on (home/.hammerspoon/appearance.lua). Linux cannot be asked, so
# the links are made once, dark; from then on they follow the terminal
# attached to tmux (home/.tmux.conf), or `scripts/appearance.sh light`.
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
