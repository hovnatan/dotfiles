#!/bin/bash
# PreToolUse hook (Bash matcher): deterministic enforcement of the CLAUDE.md
# git rules. git commit / git push (force pushes included), and commands that
# would move a pinned submodule off the commit its superproject records,
# always get a permission prompt so the user approves each one explicitly.
# Blind spot: `cd <sub> && git checkout ...` - the hook never sees the cwd.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

case "$cmd" in
  *git*) ;;
  *) exit 0 ;;
esac

emit() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

force_re='(^|[[:space:]])(--force-with-lease(=[^[:space:]]*)?|--force|-f)([[:space:]]|$)'
submodule_re='(^|[[:space:]])submodule([[:space:]]|$)'
remote_re='(^|[[:space:]])--remote([[:space:]]|$)'
foreach_re='(^|[[:space:]])foreach([[:space:]]|$)'
moving_re='(^|[[:space:]])(checkout|pull|merge|rebase|reset)([[:space:]]|$)'
dash_c_re='(^|[[:space:]])-C[[:space:]]+([^[:space:]]+)'
pin_msg='SUBMODULE PIN MOVE - requires explicit user approval (git-guard hook, per CLAUDE.md: never move a pinned submodule off the commit its superproject records).'
ask_reason=''

# Split compound commands on ; & | and inspect each simple command.
while IFS= read -r seg; do
  [[ $seg =~ (^|[[:space:]])git[[:space:]] ]] || continue

  # Submodule pin moves. `git submodule update [--init] [--recursive]` is the
  # sanctioned way to restore pins and stays unprompted; --checkout does not
  # trip moving_re because the word is preceded by '-', not whitespace.
  if [[ $seg =~ $submodule_re ]]; then
    if [[ $seg =~ $remote_re ]]; then
      emit ask "$pin_msg"
    fi
    if [[ $seg =~ $foreach_re ]] && [[ $seg =~ $moving_re ]]; then
      emit ask "$pin_msg"
    fi
  elif [[ $seg =~ $moving_re ]] && [[ $seg =~ $dash_c_re ]]; then
    # BASH_REMATCH is from dash_c_re, the last match evaluated.
    target=${BASH_REMATCH[2]}
    if [[ -n $(git -C "$target" rev-parse --show-superproject-working-tree 2>/dev/null || true) ]]; then
      emit ask "$pin_msg"
    fi
  fi

  if [[ $seg =~ (^|[[:space:]])push([[:space:]]|$) ]]; then
    if [[ $seg =~ $force_re ]]; then
      emit ask "FORCE PUSH - requires explicit user approval (git-guard hook, per CLAUDE.md: never force push unless explicitly requested)."
    fi
    ask_reason='git push requires explicit user approval (git-guard hook, per CLAUDE.md).'
  elif [[ $seg =~ (^|[[:space:]])commit([[:space:]]|$) ]]; then
    : "${ask_reason:=git commit requires explicit user approval (git-guard hook, per CLAUDE.md).}"
  fi
done <<< "$(printf '%s\n' "$cmd" | tr ';&|' '\n')"

if [[ -n $ask_reason ]]; then
  emit ask "$ask_reason"
fi
exit 0
