# Nix package set for Linux machines: the curated CLI tools this repo gets
# from Nix instead of the distro's package manager, pinned by flake.lock so
# every machine resolves the same builds. Installing Nix itself: README.md,
# "Nix packages (Linux)".
#
# Install:  nix profile add path:$HOME/.dotfiles/nix         (once per machine)
# Apply:    nix profile upgrade nix                            (after the list or lock changed;
#                                                               `dotup` does this on Linux)
# Bump:     nix flake update --flake path:$HOME/.dotfiles/nix  then commit flake.lock and apply
# Inspect:  nix profile list; nix flake metadata path:$HOME/.dotfiles/nix
#
# Curated, not dumped: add packages here by hand, each with a comment saying
# why it is here and when, like the Brewfile. A package installed ad hoc with
# `nix profile add nixpkgs#foo` is unpinned (it follows whatever the registry
# resolves that day) and invisible to other machines; move it into this list.
#
# Gotchas:
# - Always address this flake as `path:...`. A bare path inside a git repo
#   becomes a git+file flake: untracked files are invisible to it (a new
#   file does not exist until `git add`) and the whole repo is copied to the
#   store on every evaluation.
# - The profile entry is named after this directory (`nix`), not after the
#   buildEnv. `nix profile upgrade <wrong name>` only warns "does not match
#   any packages" and exits 0, so a typo there silently upgrades nothing.
# - macOS packages live in the Brewfile; this flake builds for Linux only.
{
  description = "dotfiles: curated Linux packages, pinned by flake.lock";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      # One buildEnv rather than one profile entry per package, so the whole
      # set installs, upgrades and rolls back as a unit.
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.buildEnv {
            name = "dotfiles-packages";
            extraOutputsToInstall = [ "man" ];
            paths = [
              # tmux -- latest release; Ubuntu 24.04 ships 3.4 (2026-09-23)
              pkgs.tmux
              # fish -- interactive shell, config in home/.config/fish with its
              # plugins vendored there; zsh stays the login shell (2026-09-23)
              pkgs.fish
              # fzf, fd -- the fish fzf plugin's ctrl-t/alt-c search
              # (FZF_FIND_FILE_COMMAND in home/.config/fish/config.fish) (2026-09-23)
              pkgs.fzf
              pkgs.fd
              # neovim -- fish's EDITOR and its n/tc/jc abbreviations (2026-09-23)
              pkgs.neovim
              # ripgrep -- rg, also behind fish's g/rgh abbreviations (2026-09-23)
              pkgs.ripgrep
            ];
          };
        });
    };
}
