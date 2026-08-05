#!/usr/bin/env bash
# Package and install the reveal-scm-inline VS Code extension from source.
# On a Remote-SSH server it installs into ~/.vscode-server; on a local machine
# it uses the 'code' CLI. Reload the VS Code window afterwards.
set -euo pipefail

command -v npx >/dev/null || { echo "npx (node) is required to package the extension" >&2; exit 1; }

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ext_dir="$dotfiles_dir/.config/vscode/reveal-scm-inline"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
vsix="$tmp_dir/reveal-scm-inline.vsix"

(cd "$ext_dir" && npx --yes @vscode/vsce package --allow-missing-repository -o "$vsix")

if [ -d "$HOME/.vscode-server/cli/servers" ]; then
    # Remote-SSH host: use the newest server build's CLI so the extension
    # lands in ~/.vscode-server/extensions (shared across server builds).
    cli="$(ls -t "$HOME"/.vscode-server/cli/servers/*/server/bin/code-server | head -1)"
else
    cli="code"
fi

"$cli" --install-extension "$vsix"
echo "Installed reveal-scm-inline. Reload the VS Code window to activate."
