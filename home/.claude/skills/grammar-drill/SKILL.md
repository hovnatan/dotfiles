---
name: grammar-drill
description: A 10-minute English grammar drill built from my own past mistakes. Optional argument - a pattern name, or "mixed".
disable-model-invocation: true
---

# Grammar drill

A short fix-the-sentence drill for my recurring English mistakes. The
sentences are real ones I wrote, so they live in my private dotfiles, not
here:

```text
~/.config/grammar-drill/bank.md     sentences by pattern, `wrong => fixed`
~/.config/grammar-drill/sources.md  where my writing lives (Slack token file)
~/.local/state/grammar-drill/history.tsv   one line per finished drill
~/.local/state/grammar-drill/last_harvest  UTC date of the last harvest
```

If `bank.md` is missing, `~/.dotfiles-private` is not cloned or linked on
this machine: say so and stop.

## Run a drill

1. **Harvest when stale.** When `last_harvest` is missing or more than 7 days
   old, or the argument is `harvest`, run the harvest below first, then carry
   on (or stop, for `harvest`).
2. **Pick the pattern.** Use the argument when given. Otherwise read
   `history.tsv` and take the pattern with the lowest last score, breaking
   ties by the one practised longest ago; a pattern never drilled comes first.
   `mixed` draws from every pattern and hides which is which.
3. **Build 10 pattern sentences**, wrong versions only. When the pattern has
   fewer than 10 lines, fill the rest with new sentences in the same voice and
   topics (terminals, Slack about deploys, quantum jobs), marked `(new)`.
   Make 3 of the 10 harder: each keeps its target mistake and gains a second
   one from another pattern in the bank (e.g. an articles line that also drops
   a past tense), so I have to read the whole sentence, not hunt for one slot.
4. **Add 5 stretch sentences** from 5 different topics in the stretch list
   below, each written fresh with one mistake typical of that topic. Prefer
   topics I missed last time (`stretch:<topic>` lines at `0/1` in
   `history.tsv`), then ones never shown.
5. **Show all 15** numbered in one random order, with nothing marking the
   harder or stretch ones. Name the pattern (except in `mixed`) and say 5 more
   come from other topics; give no rules. Ask me to reply with all 15 fixed
   sentences in one message.
6. **Grade each answer.** Any grammatical fix that keeps the meaning counts,
   not only the bank's version. A sentence is right only when every planted
   mistake in it is fixed. Mark each one right or wrong; for a wrong one give
   the corrected sentence and a one-line reason naming each missed mistake's
   pattern or topic. Also flag a new mistake I introduced, but leave it out of
   the score. Done when all 15 are graded, the pattern score (of 10) and the
   stretch score (of 5) are given apart, and the rule of the pattern and of
   each missed stretch topic is stated once, in one or two lines each.
7. **Record it.** Append to `history.tsv` (create the folder and a header
   `date<TAB>pattern<TAB>score` on first use) one line for the pattern, score
   as `7/10` (a `mixed` drill: one line per pattern it touched), and one
   `stretch:<topic>` line per stretch sentence, `1/1` or `0/1`. Step 2 picks
   only bank patterns, never `stretch:` lines.

## Stretch topics

Hard intermediate-to-advanced grammar of the kind "English Grammar in Use"
covers, chosen to have nothing to do with my bank patterns. Write original
sentences; do not copy the book's examples.

```text
third-conditional      If I had known, I would have told you.
mixed-conditional      If I had taken that job, I would be in Boston now.
wish                   I wish I had / I wish it would stop / if only
modal-perfect          should have, must have, can't have, might have done
used-to                used to do vs be used to doing vs get used to doing
reported-speech        tense backshift, reported questions (asked where it was)
gerund-or-infinitive   stop/remember/try/forget + -ing vs to, meaning changes
relative-clauses       non-defining commas, whose, preposition placement
causative              have/get something done
inversion              Never have I..., Hardly had..., Not only did...
reporting-passive      is said to be, is thought to have done
time-and-past          It's time we left; I'd rather you didn't
quantifiers            few vs a few, little vs a little, neither/either
concession             despite/in spite of + -ing vs although + clause
so-such                so + adjective vs such (a) + noun
future-perfect-cont    will have done vs will be doing
participle-clauses     Having finished..., Built in 1990, ...
```

## Harvest

Collect what I wrote since `last_harvest` and turn my fresh mistakes into
bank lines. Raw text goes to a new `mktemp -d` folder, deleted at the end:
it holds work messages.

1. **Gather my writing.**
   - Prompts: entries of `~/.claude/history.jsonl` whose `timestamp` (epoch
     ms) is after `last_harvest`, using the `display` field. Drop slash
     commands, `!` commands, pasted blocks and anything under 25 characters.
   - Slack: load the token as `sources.md` says, then `slack api
     search.messages` with `query="from:<me> after:<last_harvest>"`,
     `count=100`, every page (`<me>` is `auth.test`'s `user_id`; stderr apart
     from the JSON). Read-only: no posting, reacting or marking read.
2. **Keep only text I typed.** Set aside posts drafted by Claude or a bot
   under my name (`ai-agent triage`, `[DRAFT ...]`, long structured reports),
   non-English text, and dictation artifacts (a misheard word such as
   "Cloud Code" is speech-to-text, not grammar).
3. **Pick the mistakes.** Grammar slips only, not typos, lowercase or
   missing apostrophes. Done when every kept message has been read.
4. **Append to `bank.md`**, each under its pattern's code block as
   `wrong => fixed`, skipping near-duplicates of existing lines. Swap names,
   hosts and work details for neutral stand-ins and fix unrelated typos, so
   each line drills one thing. A mistake that fits no pattern starts a new
   `## <pattern>` heading with a one-line rule.
5. **Close out.** Write today's UTC date to `last_harvest`, delete the temp
   folder, and tell me the lines added per pattern, quoting new patterns in
   full. The bank is in a git repo: commit it there only when I ask.
