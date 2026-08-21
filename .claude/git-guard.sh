#!/bin/bash
# PreToolUse hook (Bash matcher): deterministic enforcement of the CLAUDE.md
# git rules. Destructive pushes (force in any spelling, remote-ref deletes,
# --mirror) always get a permission prompt so the user approves each one
# explicitly. Everything else -- commit, plain push, submodule pin moves --
# runs unprompted: those rules are behavioral (Claude acts only when asked),
# and a pin move is locally reversible via `git submodule update`.
set -euo pipefail

# Runs on every Bash tool call: prescreen the raw payload with builtins so
# the common non-git case exits without forking jq.
payload=''
IFS= read -r -d '' payload || true
[[ $payload == *git* ]] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<< "$payload" 2>/dev/null) || exit 0

emit() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

push_msg='DESTRUCTIVE PUSH - requires explicit user approval (git-guard hook, per CLAUDE.md: never force push unless explicitly requested; force/delete/mirror pushes rewrite or remove remote refs).'

# Split compound commands on ; & | and inspect each simple command.
while IFS= read -r seg; do
  [[ $seg =~ (^|[[:space:]])git[[:space:]] ]] || continue
  [[ $seg =~ (^|[[:space:]])push([[:space:]]|$) ]] || continue

  # Classify each token rather than grepping for flag spellings, so
  # short-option clusters (-fu), +refspec forces, and :refspec deletes are
  # caught alongside the long flags.
  read -ra toks <<< "$seg"
  for tok in "${toks[@]}"; do
    case "$tok" in
      --force|--force-with-lease|--force-with-lease=*|--mirror|--delete) emit "$push_msg" ;;
      --*) ;;
      -*[fd]*) emit "$push_msg" ;;
      +*|:*) emit "$push_msg" ;;
    esac
  done
done <<< "${cmd//[;&|]/$'\n'}"
exit 0
