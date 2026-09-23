# Homebrew bundle for macOS machines: the curated list of casks, Mac App
# Store apps and VS Code extensions this machine should have. Command-line
# tools come from Nix instead (nix/flake.nix, the `common` list shared with
# the Linux boxes, since 2026-09-23); only formulae that belong with the Mac
# apps stay here (mas drives this file's App Store entries, duti sets
# default apps).
#
# Restore:  brew bundle --file=~/.dotfiles/Brewfile
# Drift:    brew bundle check --file=~/.dotfiles/Brewfile --verbose   (in file, not installed)
#           brew bundle cleanup --file=~/.dotfiles/Brewfile           (installed, not in file)
#           `dotup` (scripts/update.sh) prints both on macOS.
#
# Curated, not dumped: edit this file by hand. `brew bundle dump --force`
# drops every comment and re-adds App Store apps left out on purpose (the
# drift report lists them). Apps with no cask (Safari, Meta Muse) are
# not listed.
#
# Adding a package: give it a comment saying why it is here, e.g.
#   # duti -- make VS Code the default for .qasm files (2026-08-05)
# A future "do I still need X?" is then a read, not an archaeology dig
# through shell history and old agent sessions.
#
# Maintenance gotchas:
# - Agent shells have no tty, so a cask that needs sudo (pkg installers,
#   /usr/local/bin symlinks: docker-desktop, little-snitch, tunnelblick, zoom,
#   ...) fails there - and a failed `--adopt` rolls back by deleting the
#   adopted app (Docker.app was lost this way on 2026-09-22). Adopt one cask
#   first; hand anything needing sudo (casks, `mas uninstall`) to the user
#   (see "Password prompts" in the global CLAUDE.md).
# - `brew uninstall` autoremoves orphaned dependencies (removing one CLI took
#   50 formulae with it). Preview with `brew autoremove --dry-run`.
# - `brew uninstall X` removes one installed version; older kegs stay (gcc,
#   libomp, libpq all left one). Use `--force` to take every version, then
#   run `brew missing`: older kegs of autoremoved deps can be left with broken
#   links - remove them with `brew uninstall --force --ignore-dependencies`.
# - Casks marked auto_updates update themselves, so their recorded version
#   lagging is not drift. brew reads the app bundle's own version instead,
#   and does flag the cask when the app itself is older than the tap (its
#   updater never ran: ChatGPT.app sat at 26.901 while an adopt recorded
#   26.917, 2026-09-23). Open the app to let it update, or
#   `brew upgrade --cask <name>`.

# duti -- make VS Code the default for .qasm files (2026-08-05)
brew "duti"
# Mac App Store command-line interface
brew "mas"
# Apps. Contexts is left out: its download CDN serves an expired TLS cert,
# so the cask cannot install (2026-09-22).
cask "alt-tab"
cask "ankerwork"
cask "chatgpt"
cask "claude"
cask "discord"
cask "docker-desktop"
cask "dropbox@beta"
cask "ghostty"
cask "google-chrome"
cask "google-chrome@beta"
cask "google-drive"
cask "hammerspoon"
cask "homerow"
cask "iina"
cask "keepassxc"
cask "libreoffice"
cask "little-snitch"
cask "lm-studio"
cask "lookaway"
cask "microsoft-teams"
cask "postico"
cask "protonvpn"
cask "superwhisper"
cask "tailscale-app"
cask "temurin"
cask "tor-browser"
cask "tunnelblick"
cask "visual-studio-code"
cask "vlc"
cask "zoom"
cask "zotero"
# Mac App Store apps (need `mas` and an App Store sign-in)
mas "Developer", id: 640199958
mas "Kindle", id: 302584613
mas "Prime Video", id: 545519333
mas "Slack", id: 803453959
mas "Telegram", id: 747648890
mas "WhatsApp", id: 310633997
mas "Windows App", id: 1295203466
mas "Xcode", id: 497799835
vscode "anthropic.claude-code"
vscode "charliermarsh.ruff"
vscode "github.vscode-github-actions"
vscode "github.vscode-pull-request-github"
vscode "ms-python.debugpy"
vscode "ms-python.python"
vscode "ms-python.vscode-pylance"
vscode "ms-python.vscode-python-envs"
vscode "ms-toolsai.jupyter"
vscode "ms-toolsai.jupyter-keymap"
vscode "ms-toolsai.jupyter-renderers"
vscode "ms-toolsai.vscode-jupyter-cell-tags"
vscode "ms-toolsai.vscode-jupyter-slideshow"
vscode "ms-vscode-remote.remote-containers"
vscode "ms-vscode-remote.remote-ssh"
vscode "ms-vscode-remote.remote-ssh-edit"
vscode "ms-vscode.remote-explorer"
vscode "vscodevim.vim"
