const vscode = require('vscode');

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('revealScmInline.reveal', (...args) => {
      // Invoked from the SCM view; args are SourceControlResourceState objects.
      const resource = args.find((a) => a && a.resourceUri);
      if (resource) {
        return vscode.commands.executeCommand('revealInExplorer', resource.resourceUri);
      }
    })
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
