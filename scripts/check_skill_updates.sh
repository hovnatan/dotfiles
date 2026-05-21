#!/usr/bin/env bash
#
# check_skill_updates.sh — report upstream updates for vendored Claude Code skills.
#
# Skills under ~/.dotfiles/.claude/skills/ are vendored (copied in), not pulled
# live, so a compromised or churning upstream can never silently change what the
# agent runs. Each vendored skill carries a `.upstream` file pinning it to a
# reviewed commit:
#
#   repo=https://github.com/owner/name
#   subdir=path/within/repo      # empty when the repo itself IS the skill
#   branch=main
#   commit=<full 40-char sha>
#
# This script compares each pinned commit against the newest upstream commit
# that touches the skill's files and prints a compare URL. It NEVER modifies
# anything — bumping a skill stays a manual, reviewed re-vendor:
#
#   1. review the compare URL
#   2. re-copy the skill at the new commit
#   3. update commit= in that skill's .upstream
#
# Needs `gh` (preferred) or `curl`+`jq`. Set GITHUB_TOKEN to lift the
# unauthenticated GitHub API rate limit on the curl path.

set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-$HOME/.dotfiles/.claude/skills}"

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi

# latest_commit <owner/repo> <branch> <subdir>
# prints: "<sha>\t<iso-date>\t<subject>"  (empty subdir => whole repo)
latest_commit() {
  local slug="$1" branch="$2" path="$3"
  local query="sha=${branch}&per_page=1"
  [ -n "$path" ] && query="${query}&path=${path}"
  local jqx='.[0].sha + "\t" + .[0].commit.committer.date + "\t" + (.[0].commit.message | split("\n")[0])'

  if command -v gh >/dev/null 2>&1; then
    local out
    if out=$(gh api "repos/${slug}/commits?${query}" --jq "$jqx" 2>/dev/null) \
       && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi

  if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local url="https://api.github.com/repos/${slug}/commits?${query}"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url" | jq -r "$jqx"
    else
      curl -fsSL "$url" | jq -r "$jqx"
    fi
    return $?
  fi

  echo "ERROR: need 'gh', or 'curl'+'jq'" >&2
  return 1
}

found=0
updates=0

for up in "$SKILLS_DIR"/*/.upstream; do
  [ -e "$up" ] || continue
  found=$((found + 1))
  name=$(basename "$(dirname "$up")")

  repo='' subdir='' branch='' commit=''
  while IFS='=' read -r key val; do
    case "$key" in
      repo)   repo=$val ;;
      subdir) subdir=$val ;;
      branch) branch=$val ;;
      commit) commit=$val ;;
    esac
  done < "$up"
  branch=${branch:-main}
  slug=$(printf '%s' "$repo" | sed -E 's#^https?://github\.com/##; s#\.git$##; s#/+$##')

  printf '%s%s%s\n' "$B" "$name" "$N"
  printf '  pinned : %s\n' "${commit:0:12}"

  if ! info=$(latest_commit "$slug" "$branch" "$subdir") || [ -z "$info" ]; then
    printf '  %sstatus : could not reach upstream%s\n\n' "$Y" "$N"
    continue
  fi
  IFS=$'\t' read -r lsha ldate lmsg <<< "$info"

  if [ "$lsha" = "$commit" ]; then
    printf '  latest : %s\n' "${lsha:0:12}"
    printf '  %sstatus : up to date%s\n\n' "$G" "$N"
  else
    updates=$((updates + 1))
    printf '  latest : %s  (%s)\n' "${lsha:0:12}" "${ldate%%T*}"
    printf '           %s\n' "$lmsg"
    printf '  %sstatus : UPDATE AVAILABLE%s\n' "$R" "$N"
    printf '  compare: https://github.com/%s/compare/%s...%s\n' "$slug" "$commit" "$lsha"
    printf '  to bump: re-vendor at %s, then set commit= in %s\n\n' "$lsha" "${up/#$HOME/\~}"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No vendored skills with a .upstream file found in $SKILLS_DIR"
  exit 0
fi

printf '%d skill(s) checked, %d with updates.\n' "$found" "$updates"
[ "$updates" -eq 0 ]
