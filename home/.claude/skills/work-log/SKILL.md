---
name: work-log
description: Add a day's work, and a Next section of the following day's tasks, to the user's Google Doc work log. Use when the user asks to write up a day, update the work log, or fill in missing days.
---

# Daily work log

The user keeps a work log in a Google Doc and asks, usually at the end of a
day, to add that day's entry. Everything identifying -- the document ids,
the project areas, who the colleagues are, which zone the user is in -- lives
OUTSIDE this file, in `~/.config/claude-worklog/routine.md`, because this
repo is public. Read that first; if it is missing the user's private dotfiles
repo is not cloned on this machine, so ask for it rather than guessing.

## Prerequisites

`gws` (the Google Workspace CLI) must be installed and authenticated. Check
with `gws auth status`; if it is missing or exits 2, run
`~/.dotfiles/scripts/install_gws.sh`, which installs the CLI and prints the
one-time browser auth steps. Its credentials are machine-local and in no
repo, so a new machine always needs the auth flow run on it.

## Writing the entry

Write with `gws`, already OAuth-authenticated AS THE USER -- edits carry
their name in version history and nothing needs sharing. The Google Drive MCP connector can read
a document but CANNOT write one: its `update_file` changes metadata only.

The log is ONE TAB PER MONTH, titled `MM/YYYY`, newest tab at index 0;
within a tab the days are newest-first too. So an entry goes at index 1 of
the CURRENT MONTH's tab -- look its `tabId` up by title, and when the month
has rolled over create it first with `addDocumentTab`
(`tabProperties: {title, index: 0}`) so it lands above the previous month.
`gws docs +write` is append-only and therefore wrong here.

```
ID=$(cat ~/.config/claude-worklog/doc-id)
# tab titles and ids
gws docs documents get --params "{\"documentId\":\"$ID\",\"includeTabsContent\":true}" |
  python3 -c 'import json,sys; [print(t["tabProperties"]["index"], t["tabProperties"]["title"], t["tabProperties"]["tabId"]) for t in json.load(sys.stdin)["tabs"]]'
gws docs documents batchUpdate --params "{\"documentId\":\"$ID\"}" --json "$(cat requests.json)"
```

`requests.json` must hold `{"requests": [...]}`, not the bare array - a
bare array fails schema validation with "Expected object". Every request's
`range`/`location` needs `tabId` alongside the index, or the edit lands in
the first tab. Order them insertText, then updateParagraphStyle and
updateTextStyle, then createParagraphBullets last: only the insert moves
indices. Note `gws` prints "Using keyring backend: keyring" ahead of the
JSON on some invocations (stdout, not stderr) - strip the first line before
parsing, or send stderr to /dev/null and check whether it is there.

`includeTabsContent` is not optional: WITHOUT it a `get` silently returns
only the first tab as `body`, with no error and no hint that other tabs
exist. With it, every tab comes back under `tabs[]` keyed by
`tabProperties.tabId`. Tabs can also be created and removed
(`addDocumentTab`, `deleteTab`), and Drive full-text search does index
non-default tabs, though its index lags an API edit by several minutes.

Build the whole entry as ONE `insertText` and compute every style range
from cumulative offsets of that block, so no request depends on existing
content. `--dry-run` renders the payload without sending it. When REWRITING
an existing entry, an equal-length swap (delete then insert the same number
of characters) leaves every other precomputed index valid, so a batch of
them needs no reordering.

## Shape of an entry

    HEADING_1    MM/DD/YYYY (City)
    HEADING_2      <area>
    HEADING_3        <area>: <task>
    bullet             HH:MM-HH:MM  what happened, with links
    HEADING_2      Next
    bullet           what tomorrow starts from, no stamp

Bullets are NORMAL_TEXT via `createParagraphBullets`
(`BULLET_DISC_CIRCLE_SQUARE`); commit and PR links are `updateTextStyle`
link ranges over words inside the bullet text. The areas in use are listed
in the private routine file -- reuse one rather than inventing a synonym.

Group by TASK, never a flat list of the day's actions: a HEADING_3 per task
labelled `<area>: <task>` (`backend: idempotency addition`), with that
task's bullets under it. A task then shows up in the document outline, and
the day reads as a handful of threads rather than scattered lines. Heading,
not bullet nesting, on purpose: `createParagraphBullets` has no
nesting-level field, it takes nesting from LEADING TABS in the inserted text
and CONSUMES them, which shifts every index after the request and breaks
style ranges computed from the insert.

Order groups, and bullets within a group, by their first source event.

## Timestamps

Every bullet opens with the span it ran over, bolded: `HH:MM` or
`HH:MM-HH:MM`, first to last source event for that bullet -- the request in
the transcript that started it through the last commit that closed it -- and
` +1` inside the bold when the span runs past midnight (next section). Never
guess a time to fill the slot; drop the stamp and say so when the source has
none. The `Next` section takes no stamps, because nothing in it has happened
yet.

Stamps are in the USER'S LOCAL TIME for that day, which is NOT this machine's
-- assume the box is UTC and the user is not. Resolve the zone per entry
rather than hardcoding it; the user moves between countries, and an entry
stamped in the wrong zone looks perfectly plausible. Two sources, both
self-updating:

- Slack profile -- `slack_read_user_profile` with no `user_id` returns a
  `Timezone:` line. Best default: it is an IANA name, so DST resolves
  correctly, and Slack clients reset it on login from a new zone.
- Git offsets, which are ground truth for where the user actually was that
  day. Commits made on this box carry the box's offset, but GitHub merge and
  squash commits carry the merging browser's, and so do laptop commits:

      git -C <repo> log --all --author="<user>" --since=<date> \
        --pretty='%ai' | grep -v '+0000'

  Only present on days something was merged, so treat it as the check on
  Slack, not the primary. Where the two disagree, git wins for that day and
  the disagreement is worth reporting -- it means a move.

If neither speaks -- no Slack connector attached, and a day whose commits
were all made on this box -- ASK. Do not fall back to the zone the last
entry used, and do not read one off the history in the private file: that
history records where the user HAS been, which is not evidence about today.
A wrong zone is invisible in the finished entry, so it is not the place to
save the user a question.

Either way, state the zone you resolved and how, in one line, BEFORE writing
the entry ("stamping in Asia/Yerevan, from Slack; the day's merges agree").
The user is in the loop when the log is written and will catch a wrong one
instantly; nothing downstream will.

So convert every git, CI and transcript time. Two traps: `git log
--date=format:` renders each commit in ITS OWN recorded zone, so local
commits and GitHub merges in one listing are hours apart --
`--date=format-local:` normalises them to the box. And times lifted from a
Google daily-agenda mail are ALREADY in the calendar's own zone; converting
those is the mistake, not leaving them.

Name the city in the date heading -- `08/31/2026 (Lisbon)` -- so entries
written on either side of a move can still be read.

## The day ends at 05:00, not at midnight

The user works past midnight, so a calendar day would split one evening's
work in two and file its tail under a date nobody associates with it. An
entry dated D covers D 05:00 up to D+1 05:00 IN THE ZONE RESOLVED ABOVE;
anything before 05:00 belongs to the previous date's entry. The cutoff sits
in the middle of the user's overnight gap; move it on fresh evidence, not
on one late night. Four things follow.

"Today" in the ask follows the same clock: asked at 01:00 on D+1 to write
up today, write D. And a date whose only work fell before 05:00 is not a
missing day -- that work is the previous date's, and no entry is added for
it.

Gather by the WINDOW, never by a calendar date in any zone. Compute both
ends once, in local time for git and GitHub and in UTC for the transcripts.
Spell the end date out: GNU date reads `05:00 + 1 day` as 05:00 in zone
+01, silently.

    D=2026-08-31; E=$(date -d "$D + 1 day" +%F); Z=Asia/Yerevan
    TZ=$Z date -d "$D 05:00" --iso-8601=seconds     # 2026-08-31T05:00:00+04:00
    TZ=$Z date -d "$E 05:00" --iso-8601=seconds     # 2026-09-01T05:00:00+04:00
    date -u -d "TZ=\"$Z\" $D 05:00" +%FT%TZ         # 2026-08-31T01:00:00Z
    date -u -d "TZ=\"$Z\" $E 05:00" +%FT%TZ         # 2026-09-01T01:00:00Z

`git log --since=<local start> --until=<local end>` takes those as they
are -- ISO with an offset, time and offset both honoured. GitHub search
takes the same form, but its range is inclusive at both ends, so
`merged:<local start>..<E 04:59:59 with offset>`. A transcript record's
`timestamp` is a UTC ISO string (`2026-08-31T21:55:57.247Z`), so compare it
to the UTC pair as strings: `.timestamp >= $A and .timestamp < $B`. On a
DST night the window is 23 or 25 hours long; `date` with the IANA zone
gets that right, a hand-written offset does not.

Stamps keep the real clock time and mark the crossing with ` +1` at the end
of the span, inside the bold: `**23:40-01:30 +1**`, `**01:45-02:30 +1**`.
Never run the clock past 24 (`25:30`).

Order by absolute time, not by the stamp text: post-midnight bullets are
the day's LAST events, and a sort on `HH:MM` would put them first. The
every-day-it-moved rule (below) uses this window too: a PR merged at 01:00
on D+1 moved on D.

## Gathering the material

Use BOTH the repos' git history (commits authored by the user that day,
which supply the links) and the sessions' transcripts under
`~/.claude/projects/*/*.jsonl` (filter records to the day's window, above,
and keep `type == "user"` messages) -- work that produced no commit, such as a
benchmark run or a policy change on a VM, only shows up there. Exclude other
people's commits.

One piece of work earns an entry on EVERY day it moved, not once on the day
it was written: the day it was opened, and again on the day it merged, each
dated by its own event. A merge days later is real work with real
consequences (who approved it, what CI was skipped) even though the diff has
not changed. Say in the later bullet what the earlier one was, so the two
read as one thread rather than a repeat. `git log` alone will not show you
the second -- a commit is dated when it was authored, not when it landed --
so check `gh pr list --search 'merged:<window>'` too, in the range form
above.

## Next day's tasks

After the day's areas, add a `Next` HEADING_2 section at the END of that
entry listing what the next day should start from. Every bullet must name
where it came from, and must come from a source -- never invent a task. The
four sources, and what to look for in each, are in the private routine file:
an OKR sheet, a team sync doc, Slack, and Gmail.

Keep it to what is genuinely actionable next, one line each, and say when a
source had nothing rather than padding the list.
