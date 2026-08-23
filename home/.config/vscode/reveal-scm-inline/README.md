# reveal-scm-inline

Adds an inline "Reveal in Explorer View" icon (list-tree) to file rows in the
VS Code Source Control view, next to the built-in Open File / Discard / Stage
icons. The built-in `git.revealInExplorer` command only lives in the right-click
menu and VS Code has no setting to promote it, hence this tiny extension.

## Install

Run `scripts/install_vscode_reveal_scm_inline.sh` (from this dotfiles repo) on
each machine. It packages the extension from source with vsce (requires
node/npx) and installs the resulting .vsix:

- on a local machine it uses the `code` CLI;
- on a Remote-SSH server it installs into `~/.vscode-server` directly.

Then reload the VS Code window. For Remote-SSH the extension must be installed
on the remote side (it is declared `extensionKind: ["workspace", "ui"]`, so VS
Code runs it next to the Git extension).

After changing the extension, re-run the install script (bump `version` in
package.json so VS Code treats it as an update).
