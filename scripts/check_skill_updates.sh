#!/usr/bin/env bash
#
# check_skill_updates.sh — report upstream updates for vendored Claude Code skills.
#
# Skills under ~/.dotfiles/home/.claude/skills/ are vendored (copied in), not pulled
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
# that touches the skill's files and prints a compare URL. By default it NEVER
# modifies anything — bumping a skill is a reviewed re-vendor:
#
#   1. review the compare URL
#   2. re-copy the skill at the new commit
#   3. update commit= in that skill's .upstream
#
# `--apply [name...]` does steps 2 and 3 for every skill with an update (or only
# the named ones): fetches the exact upstream commit, replaces the vendored
# directory with that snapshot (stale files removed, .upstream rewritten), and
# leaves the result UNCOMMITTED. The review gate moves from the compare URL to
# `git diff` in this repo: read it before committing, nothing is pushed for you.
#
#   check -> "UPDATE AVAILABLE" -> --apply -> git diff (review) -> git commit
#
# The vendored fish plugins use the same .upstream pins; point SKILLS_DIR at
# them: SKILLS_DIR=~/.dotfiles/home/.config/fish/plugins (see
# home/.config/fish/conf.d/plugins.fish).
#
# Needs `gh` (preferred) or `curl`+`jq`, plus `git` for --apply. Set
# GITHUB_TOKEN to lift the unauthenticated GitHub API rate limit on the curl path.

set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-$HOME/.dotfiles/home/.claude/skills}"

# --apply [name...]: bump instead of only report. Named skills restrict the bump;
# anything else on the command line is a usage error, not silently ignored.
apply=0
only=()
for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    -h|--help)
      echo "usage: $0 [--apply [skill...]]" >&2
      exit 0 ;;
    -*) echo "ERROR: unknown option '$arg'" >&2; exit 2 ;;
    *) only+=("$arg") ;;
  esac
done
if [ "$apply" -eq 0 ] && [ "${#only[@]}" -gt 0 ]; then
  echo "ERROR: skill names only make sense with --apply" >&2
  exit 2
fi
for name in "${only[@]}"; do
  [ -f "$SKILLS_DIR/$name/.upstream" ] \
    || { echo "ERROR: no vendored skill '$name' under $SKILLS_DIR" >&2; exit 2; }
done

# apply_update <name> <slug> <subdir> <branch> <sha>
# Replaces $SKILLS_DIR/<name> with the upstream snapshot at <sha> and rewrites
# .upstream. A shallow fetch of the one commit keeps this cheap on big repos;
# copying into a temp dir and swapping guarantees files deleted upstream do not
# linger in the vendored copy.
apply_update() {
  local name="$1" slug="$2" subdir="$3" branch="$4" sha="$5"
  local dest="$SKILLS_DIR/$name" work src staged

  work=$(mktemp -d) || return 1
  git -C "$work" init -q \
    && git -C "$work" remote add origin "https://github.com/${slug}.git" \
    && git -C "$work" fetch -q --depth 1 origin "$sha" \
    && git -C "$work" checkout -q FETCH_HEAD \
    || { echo "  ERROR: could not fetch ${slug}@${sha}" >&2; rm -rf "$work"; return 1; }

  src="$work/${subdir}"
  [ -d "$src" ] || { echo "  ERROR: ${subdir:-<repo root>} missing at ${sha}" >&2; rm -rf "$work"; return 1; }

  # Stage the new snapshot without the upstream .git (only meaningful when the
  # repo itself is the skill), then swap it into place with the pin rewritten.
  staged=$(mktemp -d) || { rm -rf "$work"; return 1; }
  cp -R "$src"/. "$staged"/ && rm -rf "$staged/.git" \
    || { rm -rf "$work" "$staged"; return 1; }
  printf 'repo=https://github.com/%s\nsubdir=%s\nbranch=%s\ncommit=%s\n' \
    "$slug" "$subdir" "$branch" "$sha" > "$staged/.upstream"
  rm -rf "$dest" && mv "$staged" "$dest" \
    || { echo "  ERROR: could not replace $dest" >&2; rm -rf "$work" "$staged"; return 1; }
  rm -rf "$work"
  printf '  %sapplied: re-vendored at %s%s\n' "$G" "${sha:0:12}" "$N"
}

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
failed=0

for up in "$SKILLS_DIR"/*/.upstream; do
  [ -e "$up" ] || continue
  name=$(basename "$(dirname "$up")")
  if [ "${#only[@]}" -gt 0 ]; then
    case " ${only[*]} " in *" $name "*) ;; *) continue ;; esac
  fi
  found=$((found + 1))

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
    if [ "$apply" -eq 1 ]; then
      apply_update "$name" "$slug" "$subdir" "$branch" "$lsha" || failed=$((failed + 1))
      echo
    else
      printf '  to bump: re-vendor at %s, then set commit= in %s\n\n' "$lsha" "${up/#$HOME/\~}"
    fi
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No vendored skills with a .upstream file found in $SKILLS_DIR"
  exit 0
fi

if [ "$apply" -eq 1 ]; then
  printf '%d skill(s) checked, %d bumped, %d failed.\n' "$found" "$((updates - failed))" "$failed"
  [ "$updates" -gt 0 ] && echo "Review with: git -C ~/.dotfiles diff --stat home/.claude/skills"
  [ "$failed" -eq 0 ]
else
  printf '%d skill(s) checked, %d with updates.\n' "$found" "$updates"
  [ "$updates" -eq 0 ]
fi
