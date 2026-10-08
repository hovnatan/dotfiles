#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): deterministic enforcement of the CLAUDE.md
# git rules. Destructive pushes (force in any spelling, remote-ref deletes,
# --mirror) always get a permission prompt so the user approves each one
# explicitly. Everything else -- commit, plain push, submodule pin moves --
# runs unprompted: those rules are behavioral (Claude acts only when asked),
# and a pin move is locally reversible via `git submodule update`.
#
# How a command is read:
#
#   echo "$(git -C r push origin '+main')"
#     | quotes and backslashes -> spaces       (bash -c "...", '+main', \git)
#     | split on ; & | ( ) ` and newlines      ($(...), subshells, pipes)
#     v
#   segment: "git -C r push origin  +main"
#     | find a token named git (or .../git), skip git's own options
#     | (-C <dir>, -c <k=v>, ...), the next token is the subcommand
#     v
#   push -> classify every later token: --force..., -f/-d clusters,
#           +refspec, :refspec -> ask
#
# It errs toward asking: `echo git push -f` prompts too. It cannot see
# through a git alias or a script file; server-side branch protection is the
# layer that holds regardless. Fails closed: when the payload cannot be read
# (no jq, bad JSON), a command that mentions git gets the prompt.
set -euo pipefail

# Runs on every Bash tool call: prescreen the raw payload with builtins so
# the common non-git case exits without forking jq.
payload=''
IFS= read -r -d '' payload || true
[[ $payload == *git* ]] || exit 0

push_msg='DESTRUCTIVE PUSH - requires explicit user approval (git-guard hook, per CLAUDE.md: never force push unless explicitly requested; force/delete/mirror pushes rewrite or remove remote refs).'

# Printed without jq, so the fail-closed path below works without it too.
# The reasons are fixed strings with no characters that need escaping.
emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

if ! command -v jq >/dev/null; then
  emit 'git-guard hook cannot inspect this command: jq is not on PATH. Approve only if it is not a force, delete or mirror push.'
fi
if ! cmd=$(jq -er '.tool_input.command | strings' <<<"$payload" 2>/dev/null); then
  emit 'git-guard hook cannot read this tool call (no tool_input.command in the payload). Approve only if it is not a force, delete or mirror push.'
fi

# Quotes and backslashes go first (to spaces, so `"+main"` stays its own
# token), then every command separator and substitution boundary splits.
cmd=${cmd//[\"\'\\]/ }
cmd=${cmd//[;&|()\`]/$'\n'}

while IFS= read -r seg; do
  read -ra toks <<<"$seg"

  # Find git, then its subcommand: the first token after it that is not one
  # of git's own options. -C, -c and the like take the next token as value.
  sub=''
  for ((i = 0; i < ${#toks[@]}; i++)); do
    [[ ${toks[i]} == git || ${toks[i]} == */git ]] || continue
    for ((j = i + 1; j < ${#toks[@]}; j++)); do
      case "${toks[j]}" in
        -C | -c | --git-dir | --work-tree | --namespace | --config-env | --super-prefix) j=$((j + 1)) ;;
        -*) ;;
        *)
          sub=${toks[j]}
          break
          ;;
      esac
    done
    break
  done
  [[ $sub == push ]] || continue

  # Classify each token after the subcommand rather than grepping for flag
  # spellings, so short-option clusters (-fu), +refspec forces, and
  # :refspec deletes are caught alongside the long flags.
  for tok in "${toks[@]:j+1}"; do
    case "$tok" in
      --force | --force-with-lease | --force-with-lease=* | --mirror | --delete) emit "$push_msg" ;;
      --*) ;;
      -*[fd]*) emit "$push_msg" ;;
      +* | :*) emit "$push_msg" ;;
    esac
  done
done <<<"$cmd"
exit 0
