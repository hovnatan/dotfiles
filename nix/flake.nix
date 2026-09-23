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
          pkgs = nixpkgs.legacyPackages.${system};

          # Every machine: Linux boxes and Macs get the same tools at the
          # same versions (2026-09-23). The macOS entries came from the
          # Brewfile's formulae, their comments carried over.
          common = [
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
            # fd -- the fish fzf plugin's file search (FZF_FIND_FILE_COMMAND
            # in home/.config/fish/config.fish)
            pkgs.fd
            # fish -- interactive shell, config in home/.config/fish with its
            # plugins vendored there; the login shell stays the account's own
            pkgs.fish
            # fzf -- the fish fzf plugin's ctrl-t/alt-c pickers
            pkgs.fzf
            # GitHub command-line tool
            pkgs.gh
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
            # Sophisticated file transfer program
            pkgs.lftp
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
            # ripgrep -- rg, also behind fish's g/rgh abbreviations
            pkgs.ripgrep
            # rsync 3.x; Apple's /usr/bin/rsync is openrsync (see ssh_folder_sync.sh)
            pkgs.rsync
            # Static analysis and lint tool, for (ba)sh scripts
            pkgs.shellcheck
            # tmux -- latest release; Ubuntu 24.04 ships 3.4
            pkgs.tmux
            # Markup-based typesetting system
            pkgs.typst
            # Extremely fast Python package installer and resolver
            pkgs.uv
            # Internet file retriever
            pkgs.wget
          ];

          # Linux only. macOS ships its own zsh as the default shell.
          linux = [
            # zsh -- the same zsh on every Linux box; it wins on PATH over the
            # distro's, and the login shell stays the account's (2026-09-23)
            pkgs.zsh
          ];

          darwin = [ ];
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
