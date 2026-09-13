---
name: label
description: Label this conversation with its task, `/label <task>`, so the prompt bar, the /resume picker, claude.ai and the tmux session all show `<name>/<task>`. Only when the user invokes it; never label a conversation on your own.
argument-hint: <task>
disable-model-invocation: true
allowed-tools: Bash(~/.claude/skills/label/label-session.sh:*)
---

Run exactly this, with the argument the user gave, and nothing else:

    ~/.claude/skills/label/label-session.sh "$ARGUMENTS"

It types `/rename <hostname>-<name>/<task>` into this session's own pane;
the rename queues behind this turn and runs the moment it ends. On success
reply with the one line it printed, the full title, and stop. On failure
quote its error and stop: do not retry with a changed task, do not run
`/rename` any other way, and do not label anything yourself.

The alphabet is letters, digits, `-` and `_`; a task the script refuses is
for the user to respell.
