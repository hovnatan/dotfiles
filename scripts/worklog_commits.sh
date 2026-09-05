#!/usr/bin/env bash
#
# worklog_commits.sh - every commit the user authored in a time window, across
# every repository of the GitHub owners the work-log skill is configured for.
# The `work-log` skill runs it to gather a day's commits.
#
# Why walk GitHub rather than the clones on this box: the clones are partial
# (only what was cloned here) and stale (whatever was last fetched), and the
# user also commits from a laptop. Why not the two obvious shortcuts:
#   - `gh search commits` indexes only each repo's DEFAULT branch, which is
#     `develop` on the main repos, so it misses `main` and feature branches.
#   - the API's `author=<login>` matches by account linkage, i.e. an email
#     GitHub has verified, so commits carrying the user's name with a blank
#     or unverified email vanish (nine such commits in July 2026).
# So this walks every branch and filters on the author's name+email text.
#
#   github-owners --> repos pushed since START --> branches --> commits in window
#   (config)          (`gh repo list`)          (branches API)  (commits API)
#   extra-repos   --> git fetch  --------------> branches --> git log per branch
#   (local clones)                             (for-each-ref)  (--since/--until)
#                                                                    |
#         keep when "name email" matches git-author-pattern, case-insensitive
#                                                                    |
#                 fold per-branch duplicates, then split on the AUTHORED date
#                        /                                  \
#          authored inside the window              authored before the window
#          = the day's WORK, one line per          = older work RELANDED by a
#            commit (rebased copies folded)          release or rebase, one line
#                                                    per batch (<=30 min apart)
#
# The window selects on the COMMITTER date, as `git log --since` does. That
# is what makes the split necessary: a release that rebases develop onto
# main, or a `pull --rebase`, rewrites every commit with a fresh committer
# date, so a day can show 35 "commits" of which none were written that day
# (2026-08-20 and 2026-09-01 in deqart_backend both did this). Those batches
# are still worth one line each -- a release is an event -- but not 35.
#
# Usage:   worklog_commits.sh START END
#          ISO 8601 with offset -- the day's window in the user's local time,
#          e.g. 2026-08-31T05:00:00+04:00 2026-09-01T05:00:00+04:00
# Output:  two TSV sections on stdout, each under a `#` header line:
#            #work      committed authored repo sha branches subject url
#                       added removed
#            #relanded  committed repo branches committer commits
#                       authored_from authored_to subjects
#          sha and url of a work row are its earliest landing; branches is
#          the union over every copy; added/removed are the commit's line
#          counts (the log quotes them per task), fetched with one extra
#          call per work commit -- the commits list API carries no stats.
#          Dates are UTC: the API normalises them, so the author's own
#          offset is NOT available here and the skill's timezone check
#          keeps using local git.
# Config:  ~/.config/claude-worklog/github-owners       one owner per line
#          ~/.config/claude-worklog/git-author-pattern  a regex, e.g. hovnatan
#          ~/.config/claude-worklog/extra-repos         optional: "<path> [<link>]"
#            per line -- local clones of repos GitHub does not host (an
#            Overleaf paper); the link, if given, fills the url column.
#          All live in the private dotfiles; `#` lines and blanks are ignored.
# Progress goes to stderr, one line per repo, so a slow run is watchable.
# A typical day is ~9 active repos, ~135 API calls plus one per work commit,
# about a minute.

set -euo pipefail
shopt -s extglob   # for the *([[:space:]]) trim in the extra-repos parser

CONF=${CLAUDE_WORKLOG_CONF:-$HOME/.config/claude-worklog}

die() { echo "worklog_commits.sh: $*" >&2; exit 1; }
log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

case "${1:-}" in
  -h|--help|'') sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
[ $# -eq 2 ] || die "usage: worklog_commits.sh START END  (ISO 8601 with offset)"

# The window is taken with whatever offset it carries and normalised to UTC:
# the API compares against UTC, and `gh repo list`'s pushedAt is UTC too, so
# one form serves both the queries and the repo prefilter below.
START=$(date -u -d "$1" +%FT%TZ 2>/dev/null) || die "cannot parse START: $1"
END=$(date -u -d "$2" +%FT%TZ 2>/dev/null) || die "cannot parse END: $2"
[[ "$START" < "$END" ]] || die "START must precede END ($START >= $END)"

# The identifying half -- who the user is, which owners -- lives in the
# private dotfiles, never in this public script.
[ -r "$CONF/github-owners" ] || die "missing $CONF/github-owners -- is ~/.dotfiles-private installed?"
[ -r "$CONF/git-author-pattern" ] || die "missing $CONF/git-author-pattern"
PATTERN=$(grep -v -E '^[[:space:]]*(#|$)' "$CONF/git-author-pattern" | head -1)
OWNERS=$(grep -v -E '^[[:space:]]*(#|$)' "$CONF/github-owners")
[ -n "$PATTERN" ] || die "$CONF/git-author-pattern is empty"
[ -n "$OWNERS" ] || die "$CONF/github-owners is empty"
# extra-repos is optional by design: a machine with nothing off GitHub has no file.
EXTRA=$( [ -r "$CONF/extra-repos" ] && grep -v -E '^[[:space:]]*(#|$)' "$CONF/extra-repos" || true )

command -v gh >/dev/null 2>&1 || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated -- run: gh auth login"

export START END PATTERN   # read by the jq programs below through $ENV

RAW=$(mktemp); OUT=$(mktemp)
trap 'rm -f "$RAW" "$OUT"' EXIT

# The name test: join author name and email into one string and regex-search
# it, ignoring case, so a match in either field keeps the commit. Repo and
# branch reach jq through $ENV rather than string interpolation, since a
# branch name may carry quotes. The subject is the message's first line with
# tabs flattened, so the TSV keeps its column count.
FILTER='.[]
  | select((.commit.author.name + " " + .commit.author.email) | test($ENV.PATTERN; "i"))
  | [.commit.committer.date, .commit.author.date, .commit.committer.name,
     $ENV.REPO, .sha[0:9], $ENV.BRANCH,
     (.commit.message | split("\n")[0] | gsub("\t"; " ")), .html_url]
  | @tsv'

while IFS= read -r owner; do
  # A commit authored inside the window reached GitHub only through a push at
  # or after the window opened, so pushedAt prunes the owner's repo list
  # (35 -> 9 on a typical day) before any per-branch call is made.
  repos=$(gh repo list "$owner" --limit 1000 --json nameWithOwner,pushedAt \
            --jq '.[] | select(.pushedAt >= $ENV.START) | .nameWithOwner' | sort) \
    || die "gh repo list $owner failed"
  log "$owner: $(grep -c . <<< "$repos" || true) repos pushed since $START"

  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    if ! branches=$(gh api --paginate -X GET "repos/$repo/branches" -f per_page=100 --jq '.[].name'); then
      log "$repo: branch listing failed, skipped"; continue
    fi

    # One commits query per branch: since/until bound it to the window, the
    # filter above keeps the user's. A commit on several branches comes back
    # once per branch and is folded below.
    n=0
    while IFS= read -r branch; do
      [ -n "$branch" ] || continue
      n=$((n + 1))
      REPO=$repo BRANCH=$branch gh api --paginate -X GET "repos/$repo/commits" \
          -f sha="$branch" -f since="$START" -f until="$END" -f per_page=100 \
          --jq "$FILTER" >> "$RAW" \
        || log "$repo@$branch: commit listing failed, skipped"
    done <<< "$branches"
    log "$repo: $n branches walked, $(wc -l < "$RAW") matches so far (with branch duplicates)"
  done <<< "$repos"
done <<< "$OWNERS"

# Second source: local clones from extra-repos, for repos GitHub does not
# host or work never pushed. Each line is "<path> [<link>]"; the link fills
# the url column for every commit, since such hosts rarely have a page per
# commit. A configured path that is missing is a finding, not a skip. Fetch
# first: a clone is only as fresh as its last fetch, and a stale one reports
# old state that looks like today's. Remote URLs are never printed -- the
# Overleaf one embeds a write token.
US=$(printf '\x1f')   # field separator for git's output: a subject may hold tabs, never this
LOCAL_PATHS=""        # "<name>\t<path>" per line, so the post-processor knows where to run git
while IFS= read -r line; do
  [ -n "$line" ] || continue
  path=${line%%[[:space:]]*}; link=${line#"$path"}; link=${link##*([[:space:]])}
  path=${path/#\~/$HOME}
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 \
    || die "extra-repos: $path is not a git checkout on this machine -- clone it or drop the line"
  git -C "$path" fetch --all --quiet --prune \
    || die "extra-repos: fetch failed in $path -- network, or an expired token in its remote URL?"
  name=$(basename "$path")
  LOCAL_PATHS+="$name	$path
"

  # Same shape as the GitHub rows: one `git log` per branch, bounded by the
  # window on committer date and filtered by the name test (`-i --author`
  # matches "Name <email>"), dates rendered in UTC to match the API. Local
  # and remote-tracking branches both walk, so unpushed work shows; the
  # remote prefix is dropped from the name so `main` and `origin/main` fold.
  n=0
  while IFS= read -r ref; do
    branch=${ref#refs/heads/}; branch=${branch#refs/remotes/*/}
    n=$((n + 1))
    TZ=UTC git -C "$path" log "$ref" --since="$START" --until="$END" -i --author="$PATTERN" \
        --date=format-local:%FT%TZ --abbrev=9 \
        --format="%cd$US%ad$US%cn$US$name$US%h$US$branch$US%s$US$link" \
      | awk -F "$US" -v OFS='\t' '{ gsub(/\t/, " ", $7); $1 = $1; print }' >> "$RAW"
  done < <(git -C "$path" for-each-ref --format='%(refname)' refs/heads refs/remotes | grep -v '/HEAD$')
  log "$name (local): $n branches walked, $(wc -l < "$RAW") matches so far (with branch duplicates)"
done <<< "$EXTRA"

# Post-process: fold duplicates, split work from relandings, fetch line
# counts for the work commits, print both sections.
LOCAL_PATHS="$LOCAL_PATHS" python3 - "$RAW" "$START" > "$OUT" <<'PY'
import os, subprocess, sys
from datetime import datetime, timedelta

raw, start = sys.argv[1], sys.argv[2]
local_paths = dict(l.split("\t", 1) for l in os.environ["LOCAL_PATHS"].splitlines() if l)

def line_counts(w):
    """(added, removed) for one work commit. GitHub: the single-commit endpoint
    carries stats, the list endpoint does not. Local clone: git show. A commit
    that cannot be counted is a finding, so fail loudly rather than print 0."""
    if w["repo"] in local_paths:
        out = subprocess.run(["git", "-C", local_paths[w["repo"]], "show", "--shortstat",
                              "--format=", w["sha"]], capture_output=True, text=True, check=True).stdout
        added = removed = 0
        for part in out.replace("\n", ",").split(","):
            if "insertion" in part: added = int(part.split()[0])
            if "deletion" in part: removed = int(part.split()[0])
        return added, removed
    out = subprocess.run(["gh", "api", f"repos/{w['repo']}/commits/{w['sha']}",
                          "--jq", "[.stats.additions, .stats.deletions] | @tsv"],
                         capture_output=True, text=True, check=True).stdout
    added, removed = out.split()
    return int(added), int(removed)
ts = lambda z: datetime.strptime(z, "%Y-%m-%dT%H:%M:%SZ")

# One landing per (repo, sha): a commit reachable from several branches came
# back once per branch, so union the branch names.
landings = {}
for line in open(raw):
    committed, authored, committer, repo, sha, branch, subject, url = line.rstrip("\n").split("\t")
    key = (repo, sha)
    if key not in landings:
        landings[key] = dict(committed=committed, authored=authored, committer=committer,
                             repo=repo, sha=sha, branches=set(), subject=subject, url=url)
    landings[key]["branches"].add(branch)

# A commit written inside the window is the day's work. Its rebased copies
# share the author date and subject but not the sha, so fold on that identity
# and keep the earliest landing's sha and url.
work, relanded = {}, []
for l in landings.values():
    if l["authored"] >= start:
        w = work.setdefault((l["repo"], l["authored"], l["subject"]), dict(l, branches=set()))
        w["branches"] |= l["branches"]
        if l["committed"] < w["committed"]:
            w.update(committed=l["committed"], sha=l["sha"], url=l["url"])
    else:
        relanded.append(l)

print("#work: authored inside the window (rebased copies folded; sha and url are the earliest landing)")
print("#committed\tauthored\trepo\tsha\tbranches\tsubject\turl\tadded\tremoved")
for w in sorted(work.values(), key=lambda w: (w["committed"], w["repo"], w["sha"])):
    added, removed = line_counts(w)
    print("\t".join([w["committed"], w["authored"], w["repo"], w["sha"],
                     ",".join(sorted(w["branches"])), w["subject"], w["url"],
                     str(added), str(removed)]))

# Older commits landing inside the window arrive in batches: a rebase gives
# every rewritten commit the same committer second, hand cherry-picks spread
# over minutes. Cut a new batch per repo and committer when the gap between
# consecutive landings exceeds 30 minutes.
print("#relanded: authored before the window, committed inside it -- a release or rebase, one line per batch")
print("#committed\trepo\tbranches\tcommitter\tcommits\tauthored_from\tauthored_to\tsubjects")
batches = []
for l in sorted(relanded, key=lambda l: (l["repo"], l["committer"], l["committed"])):
    b = batches[-1] if batches else None
    if (b and b["repo"] == l["repo"] and b["committer"] == l["committer"]
            and ts(l["committed"]) - ts(b["last"]) <= timedelta(minutes=30)):
        b["items"].append(l); b["last"] = l["committed"]; b["branches"] |= l["branches"]
    else:
        batches.append(dict(repo=l["repo"], committer=l["committer"], committed=l["committed"],
                            last=l["committed"], branches=set(l["branches"]), items=[l]))
for b in sorted(batches, key=lambda b: b["committed"]):
    authored = sorted(i["authored"] for i in b["items"])
    subjects = " | ".join(i["subject"] for i in sorted(b["items"], key=lambda i: i["authored"]))
    print("\t".join([b["committed"], b["repo"], ",".join(sorted(b["branches"])), b["committer"],
                     str(len(b["items"])), authored[0], authored[-1], subjects]))
print(f"{len(work)} work commits, {sum(len(b['items']) for b in batches)} relanded in {len(batches)} batches", file=sys.stderr)
PY

log "done: /$PATTERN/i between $START and $END"
cat "$OUT"
