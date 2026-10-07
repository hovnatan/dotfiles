# Nix package set: the curated CLI tools every machine gets from Nix, pinned
# by flake.lock so each one resolves the same builds. On Linux it replaces the
# distro's package manager for these tools; on macOS it replaces the Brewfile's
# formulae (the Brewfile keeps casks, App Store apps and VS Code extensions).
# Installing Nix itself: README.md, "Nix packages".
#
# Install:  nix profile add path:$HOME/.dotfiles/nix         (once per machine)
# Apply:    nix profile upgrade nix                            (after the list or lock changed;
#                                                               `dotup` does this)
# Bump:     nix flake update --flake path:$HOME/.dotfiles/nix  then commit flake.lock and apply
# Inspect:  nix profile list; nix flake metadata path:$HOME/.dotfiles/nix
# Check:    scripts/check_nix_flake.sh [--build]           before pushing; CI runs it
#           (.github/workflows/nix.yml): evaluation without warnings on every
#           system, every set from the binary cache, the Linux set builds
#
# Curated, not dumped: add packages here by hand, each with a comment saying
# why it is here and when, like the Brewfile. A package installed ad hoc with
# `nix profile add nixpkgs#foo` is unpinned (it follows whatever the registry
# resolves that day) and invisible to other machines; move it into this list.
#
#   common ---+--> + linux  -> packages.{x86_64,aarch64}-linux.default
#             +--> + darwin -> packages.aarch64-darwin.default
#
# Almost everything lives in `common`, so Linux boxes and Macs stay nearly
# identical; the per-OS lists hold only the exceptions.
#
# Gotchas:
# - Always address this flake as `path:...`. A bare path inside a git repo
#   becomes a git+file flake: untracked files are invisible to it (a new
#   file does not exist until `git add`) and the whole repo is copied to the
#   store on every evaluation.
# - The profile entry is named after this directory (`nix`), not after the
#   buildEnv. `nix profile upgrade <wrong name>` only warns "does not match
#   any packages" and exits 0, so a typo there silently upgrades nothing.
# - Apple Silicon only on macOS (Homebrew there lived in /opt/homebrew); add
#   x86_64-darwin to `systems` for an Intel Mac.
{
  description = "dotfiles: curated CLI packages for Linux and macOS, pinned by flake.lock";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # One buildEnv rather than one profile entry per package, so the whole
      # set installs, upgrades and rolls back as a unit.
      packages = forAllSystems (system:
        let
          # Free software only, apart from the names listed here: each needs a
          # reason, and none is built by cache.nixos.org (Hydra skips unfree),
          # so every machine compiles it after each lock bump.
          #   terraform -- BUSL since 1.6; the infra in deqart_backend/deploy_scripts
          #                is Terraform (~4.5 min to build on an 8-CPU VM)
          #   vagrant   -- BUSL since 2.3.8; Mac only, see darwin below
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" "vagrant" ];
          };

          # Every machine: Linux boxes and Macs get the same tools at the
          # same versions (2026-09-23). The macOS entries came from the
          # Brewfile's formulae, their comments carried over.
          common = [
            # actionlint -- GitHub Actions workflow linter (expressions, job
            # references, shellcheck on `run:` blocks); CI checks
            # (scripts/check.sh yaml, .github/workflows/yaml.yml) (2026-10-07)
            pkgs.actionlint
            # ansible -- agentless configuration management over ssh
            # (ansible, ansible-playbook, ansible-galaxy); its Python and
            # modules come with it, so no pip install (2026-10-05)
            pkgs.ansible
            # Microsoft Azure CLI, with its extensions declared here: Nix's az
            # runs a Python without pip, so `az extension add` fails, and
            # extensions pip-installed under another Python break on its
            # native modules (the Mac's brew-era ssh one, 2026-09-23).
            #   ssh             -- `az ssh vm` with AAD OpenSSH certificates
            #   costmanagement, quota -- in use on vm since 2026-07 (pip-
            #                      installed under apt's az, broken by Nix's)
            (pkgs.azure-cli.withExtensions (with pkgs.azure-cli-extensions; [
              ssh
              costmanagement
              quota
            ]))
            # bash 5 for `#!/usr/bin/env bash` scripts; macOS /bin/bash is 3.2
            pkgs.bashInteractive
            # chafa -- images in the terminal over ssh: Ghostty draws its Kitty
            # graphics, inside tmux too (the fish wrapper
            # home/.config/fish/functions/chafa.fish adds the flags); symbols
            # anywhere else. Known cost: it sends raw pixels, ~25 MB for a
            # full-pane screenshot, seconds to arrive over a remote link.
            # timg sends PNG (~0.7 MB for the same image) but pulls ~490 MiB
            # of ffmpeg/poppler vs chafa's ~57 MiB (2026-09-24)
            pkgs.chafa
            # GNU coreutils as gdate, gsed, ...: the g prefix keeps macOS's
            # BSD tools as the plain names, and Linux gets the same gdate, so
            # a script needing GNU date (worklog_commits.sh, the work-log
            # skill's window recipe) calls gdate everywhere (2026-09-28)
            pkgs.coreutils-prefixed
            # cowsay -- ASCII-art speech bubbles, e.g. `fortune | cowsay`
            # (2026-10-05)
            pkgs.cowsay
            # fd -- the fish fzf plugin's file search (FZF_FIND_FILE_COMMAND
            # in home/.config/fish/config.fish)
            pkgs.fd
            # fish -- interactive shell, config in home/.config/fish with its
            # plugins vendored there; the login shell stays the account's own
            pkgs.fish
            # fortune -- random quotes (fortune-mod with its bundled
            # databases), the fish greeting
            # (home/.config/fish/functions/fish_greeting.fish) (2026-10-05)
            pkgs.fortune
            # fzf -- the fish fzf plugin's ctrl-t/alt-c pickers
            pkgs.fzf
            # GitHub command-line tool
            pkgs.gh
            # GitLab CLI (glab): issues on GitLab-hosted projects, e.g.
            # iTerm2, whose GitHub mirror has issues turned off (2026-09-29)
            pkgs.glab
            # git and git-lfs, the same version everywhere; the rest of the
            # former apt_base list of deqart_backend's setup_workspace.sh
            # follows under its own name (2026-09-23)
            pkgs.git
            pkgs.git-lfs
            # GNU make 4.x; macOS ships 3.81
            pkgs.gnumake
            # Google Cloud SDK (gcloud, gsutil, bq); no extra components in use.
            # Was apt's google-cloud-cli via deqart_backend's setup_workspace.sh
            # (2026-09-23)
            pkgs.google-cloud-sdk
            # Google Workspace CLI (gws), driven by the work-log skill
            pkgs.gws
            # Improved top (interactive process viewer)
            pkgs.htop
            # hunspell with the en_US dictionary on its search path: Claude
            # Code's spell checker (home/.claude/settings.json), plus the
            # personal word list WORDLIST points at (2026-09-23)
            (pkgs.hunspell.withDicts (dicts: [ dicts.en_US ]))
            # Tools and libraries to manipulate images in select formats
            pkgs.imagemagick
            # jq -- JSON on the command line; setup_workspace.sh reads
            # devcontainer.json with it
            pkgs.jq
            # Sophisticated file transfer program
            pkgs.lftp
            # Lua 5.4, the version Hammerspoon embeds: runs its modules
            # outside the app, against stub `hs` objects
            # (scripts/tests/iterm2_bell_banners_test.sh). CI installs the
            # same attribute (.github/workflows/tests.yml); without it here
            # the test only ran locally through `nix shell` (2026-10-02)
            pkgs.lua5_4
            # markdownlint-cli2 -- Markdown linter; rules for projects without
            # a config of their own in home/.config/markdownlint, this repo's
            # in .markdownlint-cli2.yaml, CI checks
            # (.github/workflows/markdown.yml). Pinned here so a new release's
            # rules cannot fail files nobody touched, as `npx` would (2026-10-01)
            pkgs.markdownlint-cli2
            # Unified display of technical and tag data for audio/video
            pkgs.mediainfo
            # Remote terminal application
            pkgs.mosh
            # neovim -- fish's EDITOR and its n/tc/jc abbreviations
            pkgs.neovim
            # Node 24 LTS: deqart_web pins 24 (.nvmrc, CI node-version: 24)
            pkgs.nodejs_24
            # Swiss-army knife of markup format conversion
            pkgs.pandoc
            # playwright CLI; its wrapper defaults PLAYWRIGHT_BROWSERS_PATH to
            # Nix's browsers built for this exact version, so nothing is
            # downloaded and no host libraries are needed (2026-09-23)
            pkgs.playwright-test
            # PDF utilities (pdftotext, pdfinfo, ...) from poppler
            pkgs.poppler-utils
            # python3 -- stdlib-only scripts and tests (claude_tmux_run.sh,
            # ntfy_stop_test.sh); the Mac's replaces the python.org 3.12 in
            # /usr/local/bin, and on Linux it wins over /usr/bin/python3.
            # Packages go in uv projects or `uv run` scripts, not a global pip
            # (2026-09-23)
            pkgs.python3
            # Rsync for cloud storage
            pkgs.rclone
            # ripgrep -- rg; defaults in home/.config/ripgrep/rc
            pkgs.ripgrep
            # rsync 3.x; Apple's /usr/bin/rsync is openrsync (see ssh_folder_sync.sh)
            pkgs.rsync
            # ruff -- Python linter and formatter; the user config outside
            # projects is home/.config/ruff (every rule on). Replaces a stray
            # binary in /opt/homebrew/bin that no package manager owned
            # (2026-09-27)
            pkgs.ruff
            # Static analysis and lint tool, for (ba)sh scripts
            pkgs.shellcheck
            # shfmt -- shell formatter, style in .editorconfig; CI checks
            # (scripts/check.sh shell) (2026-10-05)
            pkgs.shfmt
            # stylua -- Lua formatter, style in .stylua.toml; nvim formats on
            # save (home/.config/nvim/lua/core/format.lua), CI checks
            # (.github/workflows/lua.yml) (2026-09-24)
            pkgs.stylua
            # Terraform, for deqart_backend/deploy_scripts; unfree, see pkgs above
            pkgs.terraform
            # tmux -- latest release; Ubuntu 24.04 ships 3.4
            pkgs.tmux
            # Markup-based typesetting system
            pkgs.typst
            # unzip, xz, zstd -- archive tools; macOS has no xz or zstd
            pkgs.unzip
            pkgs.xz
            pkgs.zstd
            # Extremely fast Python package installer and resolver
            pkgs.uv
            # vim -- EDITOR in home/.profile.shared
            pkgs.vim
            # Internet file retriever
            pkgs.wget
            # yamlfmt and yamllint -- YAML formatter (layout in .yamlfmt.yaml)
            # and linter (rules in .yamllint.yaml); CI checks
            # (scripts/check.sh yaml, .github/workflows/yaml.yml). Pinned here
            # since yamlfmt's output and yamllint's rules shift between
            # releases (2026-10-07)
            pkgs.yamlfmt
            pkgs.yamllint
          ];

          # Linux only. macOS ships its own zsh as the default shell.
          linux = [
            # zsh -- the same zsh on every Linux box; it wins on PATH over the
            # distro's, and the login shell stays the account's (2026-09-23)
            pkgs.zsh
          ];

          darwin = [
            # zathura -- PDF, EPUB, DjVu, PostScript and comic-book viewer, recoloured
            # to gruvbox (home/.config/zathura/zathurarc); DjVu is why not
            # sioyek (MuPDF has no DjVu). A CLI binary, no .app: start it from
            # a terminal. Mac only: the Linux boxes are headless (2026-09-24)
            pkgs.zathura
            # dbus -- the session bus zathura takes commands on: dbus-daemon
            # (scripts/macos/dbus_session.sh) and dbus-send, with which
            # scripts/appearance.sh recolours open zathura windows when the
            # system turns light or dark. macOS has no session bus of its
            # own (2026-09-29)
            pkgs.dbus
            # vagrant -- scripted VMs on the VirtualBox cask (Brewfile). Mac
            # only: the Linux boxes are cloud VMs with no hypervisor to drive,
            # and as an unfree package every machine listing it builds it
            # locally after each lock bump (2026-10-05)
            pkgs.vagrant
          ];
        in
        {
          default = pkgs.buildEnv {
            name = "dotfiles-packages";
            extraOutputsToInstall = [ "man" ];
            paths = common ++ (if pkgs.stdenv.hostPlatform.isDarwin then darwin else linux);
          };
        });
    };
}
