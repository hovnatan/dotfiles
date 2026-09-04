#!/bin/sh
# Claude Code statusLine: model + effort (blended with PS1-derived cwd/git branch)
# Regenerate/modify this file only via the statusline-setup agent.
#
# Hue budget -- one meaning per color, so nothing on the line reads two ways.
# Adding an element? Take a free treatment, or share one whose meaning already
# matches; never re-use a hue for an unrelated idea.
#
#   bold blue      path                    matches the PS1 in ~/.zshrc.shared
#   blue           cache "cold"            the entry is gone; the next request
#                                          pays a full write. The one shared
#                                          hue: blue is what "cold" looks like,
#                                          and weight keeps it apart from the
#                                          path, which is never drawn plain
#   green          branch                  matches that PS1; "*" marks dirty,
#                                          "?" a dirty check that timed out
#   yellow         gauge 50-80%            warm, but not now
#                  cache <=10m
#                  "U" update pending
#   red            gauge >=80%             act now -- nothing else, ever
#                  cache <=2m
#   cyan           model
#   bold magenta   @agent                  rare, so it gets the loud hue
#   weight only    effort ramp             2m / plain / 1m / 1;4m / 1;7m
#   dim            separators
#
# Clean/dirty is a binary, so it is a glyph rather than a hue. Yellow was the
# obvious candidate and it does not work: GitLab Light has to darken yellow to
# be legible on #fafaff, landing on #af551d -- dE 23.6 from its own red -- so a
# dirty tree read as an error at a glance. No other hue separates either (the
# best, cyan at dE 50.5, is the model's and points the wrong way semantically).
# A trailing "*" costs one column and is exact in any theme, at any size, and
# colorblind. It is also what git's own __git_ps1 uses.

# Payload fields, in ONE jq pass that prints shell assignments. @sh quotes every
# value, so the eval is safe against anything the payload can carry (quotes,
# backslashes, `$(...)` in a session name). One pass rather than one jq per
# field for two reasons: ten spawns were ~30ms of a ~40ms run, now paid every
# 60s in every session; and the per-field form was `echo "$input" | jq`, which
# under dash rewrites JSON escapes before jq ever sees them (\t and \n become
# raw control characters jq rejects, \\ collapses), so one such escape anywhere
# in the payload blanked every field. A missing key becomes "", a value of the
# wrong shape becomes "" or "na" rather than an error, since any jq error here
# would blank the whole line. The clock comes from the same pass (`now`), so
# nothing below calls `date` -- which also keeps the transcript fallback off
# GNU-only `date -d`, the one thing that made it silently dead on macOS.
eval "$(jq -r '
  def s(f): (f // "" | tostring);
  @sh "model_id=\(s(.model.id))",
  @sh "model_name=\(s(.model.display_name))",
  @sh "effort=\(s(.effort.level))",
  @sh "cwd=\(s(.workspace.current_dir))",
  @sh "ctx_used=\(s(.context_window.used_percentage))",
  @sh "agent_name=\(s(.agent.name))",
  @sh "session_name=\(s(.session_name))",
  @sh "transcript=\(s(.transcript_path))",
  @sh "running_version=\(s(.version))",
  @sh "now=\(now | floor)",
  @sh "cache_expires=\(if .prompt_cache == null then ""
                       else ((.prompt_cache.expires_at | numbers | floor | tostring) // "na") end)",
  @sh "cache_mark=\(if ((.prompt_cache // {}) | has("recache_tokens_if_cold") and .recache_tokens_if_cold == null)
                    then "~" else "" end)"
' 2>/dev/null)"

# Anything that reaches $(( )) must be an integer: dash treats a non-integer
# operand as a fatal error, not a wrong number, and a fatal error here draws
# an empty line instead of a degraded one.
case $now in ''|*[!0-9]*) cache_expires=na ;; esac
case $cache_expires in ''|na) ;; *[!0-9]*) cache_expires=na ;; esac

# The model name is contracted to its first two letters plus the version, and
# the 1M-context marker is glued straight on: "Opus 5 (1M context)" -> "Op5[1m]",
# "Haiku 4.5" -> "Ha4.5". Two letters is the shortest prefix that still separates
# the families in play (Opus / Sonnet / Haiku / Fable), and the version is what
# actually changes under me, so it stays whole. A display name that does not fit
# the "<word> <version>" shape is left alone rather than mangled. The marker is
# rebuilt from the id, not the display name: Sonnet 5 and Fable 5.1 carry [1m]
# in the id while their display names say nothing about it.
model=$(printf '%s\n' "$model_name" |
  sed -E -e 's/ \(1M context\)$//' -e 's/^(..)[^ ]* ([0-9].*)$/\1\2/')
case "$model_id" in
  *"[1m]"*) model="${model}[1m]" ;;
esac

# Effort is a magnitude, so it climbs in weight rather than hue: faint ->
# normal -> bold -> bold underlined -> inverted chip (low/medium/high/xhigh/max;
# ultracode reports xhigh). Every hue on this line is already spoken for, and
# the previous ramp proved why that matters -- it drew `medium` in the model's
# own cyan, so "Opus 5 [1m] medium" rendered as one unbroken run, and `xhigh`
# in the agent's magenta. Weight also stays ordinal under any palette, where a
# hue ramp only reads as a climb if the theme's luminances happen to line up:
# under GitLab Light the old `xhigh` and `max` were the same #583cac, since
# ghostty leaves `bold-color` unset and bold changes weight, not color.
# Omitted entirely when the payload does not report it.
# Two-letter labels: the weight ramp already carries the magnitude, so the word
# only has to be recognisable, not readable. An unknown level keeps its full
# name -- a new level should look unfamiliar rather than be silently truncated
# into one of the five below.
eff=""
if [ -n "$effort" ]; then
  case "$effort" in
    low) ecolor='\033[2m'; elabel='lo' ;;
    medium) ecolor=''; elabel='md' ;;
    high) ecolor='\033[1m'; elabel='hi' ;;
    xhigh) ecolor='\033[1;4m'; elabel='xh' ;;
    max) ecolor='\033[1;7m'; elabel='mx' ;;
    *) ecolor=''; elabel="$effort" ;;
  esac
  eff=" ${ecolor}${elabel}\033[0m"
fi

# Abbreviate cwd to match PS1's path_abbrev: $HOME -> ~, then shorten every
# parent path component to its first character, keeping the last component full.
case "$cwd" in
  "$HOME"*) full_path="~${cwd#$HOME}" ;;
  *) full_path="$cwd" ;;
esac

old_ifs=$IFS
IFS='/'
set -f
set -- $full_path
set +f
IFS=$old_ifs

if [ "$#" -le 1 ]; then
  path="$full_path"
else
  first="$1"
  shift
  if [ "$first" = "~" ]; then
    path="~/"
  else
    path="/"
  fi
  while [ "$#" -gt 1 ]; do
    part="$1"
    if [ -n "$part" ]; then
      path="${path}${part%"${part#?}"}/"
    else
      path="${path}/"
    fi
    shift
  done
  path="${path}${1}"
fi

# Git branch, always green, with a trailing "*" when the tree is dirty -- the
# same shape as git_prompt in ~/.zshrc.shared, so one repo never reads two ways
# on one screen. See the glyph note in the hue budget above for why the dirty
# state is not a second color.
#
# The dirty check is bounded to one second. --no-optional-locks keeps this
# script from ever writing the index, which also means git cannot persist the
# stat data it refreshes: after a pull, a branch flip or an mtime sweep every
# run re-stats the whole tree (8-10s per run on a 40k-file checkout, measured)
# and, with the line now re-run every 60s, nothing ends the regime until some
# other command writes the index. One second is generous for the normal case
# (~10ms); past it the dirty state is shown as "?" rather than guessed, and the
# git child is killed rather than left to run on after the shell is aborted.
# `timeout` is coreutils; where it is missing the call runs unbounded, as before.
bounded=""
if command -v timeout >/dev/null 2>&1; then
  bounded="timeout 1"
elif command -v gtimeout >/dev/null 2>&1; then
  bounded="gtimeout 1"
fi
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ref=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$ref" ] && ref=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    dirty=""
    status=$($bounded git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    if [ $? -eq 124 ]; then
      dirty="?"
    elif [ -n "$status" ]; then
      dirty="*"
    fi
    branch=" \033[32m(${ref}${dirty})\033[0m"
  fi
fi

# Session name (set via -n or /rename; absent on unnamed sessions) minus
# the "<hostname>-" prefix these sessions carry for claude.ai's sake (see
# ~/.dotfiles/scripts/claude_tmux_run.sh): the machine is this one, and the
# 20 characters (17 + "...") that keep the line short are better spent on
# the name and its task label. Parameter expansion only: this runs on
# every refresh.
sname=""
if [ -n "$session_name" ]; then
  session_name="${session_name#"$(hostname)-"}"
  if [ "${#session_name}" -gt 20 ]; then
    session_name="${session_name%"${session_name#?????????????????}"}..."
  fi
  sname="\033[1m${session_name}\033[0m \033[2m|\033[0m "
fi

# Main-thread agent name (absent unless the session is running as a custom
# agent type via --agent / a .claude/agents/*.md slug). Rare and worth
# noticing, and magenta is reserved for it alone, so it gets the hue in bold
# rather than a dim aside.
agent=""
if [ -n "$agent_name" ]; then
  agent=" \033[1;35m@${agent_name}\033[0m"
fi

# Context window usage, dim until 50% then yellow/red by fullness, so a
# healthy line stays quiet and only a filling window draws the eye (absent
# until first API response)
ctx=""
if [ -n "$ctx_used" ]; then
  ctx_pct=$(printf '%.0f' "$ctx_used")
  if [ "$ctx_pct" -ge 80 ]; then
    ccolor='\033[31m'
  elif [ "$ctx_pct" -ge 50 ]; then
    ccolor='\033[33m'
  else
    ccolor='\033[2m'
  fi
  ctx=" \033[2m|\033[0m ${ccolor}Ctx${ctx_pct}%\033[0m"
fi

# Prompt-cache countdown: how long the conversation's cached prefix stays
# readable, so a pause can be taken knowing whether the next request costs a
# cache read or a cache write of the whole context.
#
# Two sources, in order of authority:
#
#   payload.prompt_cache   measured. expires_at is the last request's dispatch
#                          (or the last cache touch, which never surfaces as a
#                          message) plus the TTL the server actually applied,
#                          and it is exact. null when the last response carried
#                          no cache tokens at all (caching disabled, a gateway
#                          that reports none): that is "na", not "cold" --
#                          nothing expired. The tracker behind it is PER
#                          PROCESS and starts empty, so the key is absent until
#                          this process completes its first request --
#                          precisely the just-resumed session where the answer
#                          matters most.
#
#   the transcript         inferred, to fill that gap. The last main-thread
#                          reply, dated from the user/tool_result line that
#                          dispatched it -- the cache lifetime runs from request
#                          START and generation time counts against it, while a
#                          reply's own timestamp is written as its blocks
#                          finish (p99 a minute later, maxima of four) -- plus
#                          the TTL that reply's usage recorded (ephemeral_1h vs
#                          ephemeral_5m: this account drops to 5m under
#                          overage), carried forward across pure-hit replies the
#                          way the tracker does. Synthetic replies ("No response
#                          requested." at resume, API errors) are skipped: they
#                          never touched the cache. Sidechain (subagent) replies
#                          are skipped: they cache a different prefix. Parsed
#                          with jq, not a regex, so a timestamp quoted inside a
#                          tool result cannot win, and a line the tail cut in
#                          half is dropped rather than misread.
#
#   neither                "na". A brand-new session, a transcript with no
#                          reply in it, or one this process cannot read. Shown
#                          rather than hidden: an empty slot is
#                          indistinguishable from a field that has not drawn
#                          yet, and "no answer" is itself the answer.
#
# A leading "~" means unconfirmed: the number is real but the next request may
# not hit the entry it describes. Every inferred value carries it, "cold"
# included -- the transcript is only a lower bound on the last touch, since
# Claude Code's own side requests (title, memory, summaries) can refresh the
# entry without writing a main-thread line. A measured value carries it when a
# drop is pending (recache_tokens_if_cold is null: /compact, rewind, a
# microcompact): the entry is warm, but the next request rewrites from the
# first replaced position.
#
# The 2MB tail covers every transcript on this machine (the last reply is at
# most 182KB from EOF); the whole-file pass behind it exists for a single
# multi-megabyte line (an image tool result) splitting the tail, so it is
# skipped when the file is no bigger than the tail was, and costs ~0.5s on a
# 44MB transcript when it does run. This path only runs until the session's
# first response; the measured source then takes over.
#
# Whole minutes down to 1m, then seconds; colour bands follow the LABEL (red
# through "2m", yellow through "10m", blue for "cold") so one number never
# wears two colours.
# The label is dropped because a duration is the only thing on the line
# measured in time (Ctx is the sole other gauge and it is a %), and "cold" --
# the state that needs a word -- says what the number was counting. The number
# can lag the refresh interval (statusLine.refreshInterval in settings.json,
# armed only when the status line mounts: a running session needs a reload to
# pick it up), but a MEASURED flip to "cold" is exact: Claude Code schedules a
# status line refresh at expiry.
if [ -z "$cache_expires" ]; then
  if [ -r "$transcript" ]; then
    infer='
      reduce (inputs | fromjson? // empty | select(.isSidechain == false)) as $m
        ({prev: null, anchor: null, ttl: 3600};
         if $m.type == "user" then .prev = $m.timestamp
         elif $m.type == "assistant" and $m.message.model != "<synthetic>" then
           .anchor = (.prev // $m.timestamp)
           | ($m.message.usage.cache_creation // {}) as $cc
           | if ($cc.ephemeral_1h_input_tokens // 0) > 0 then .ttl = 3600
             elif ($cc.ephemeral_5m_input_tokens // 0) > 0 then .ttl = 300
             else . end
         else . end)
      | select(.anchor != null)
      | (.anchor | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) + .ttl | floor'
    cache_expires=$(tail -c 2000000 "$transcript" 2>/dev/null | jq -rRn "$infer" 2>/dev/null)
    if [ -z "$cache_expires" ] && [ $(( $(wc -c < "$transcript") )) -gt 2000000 ]; then
      cache_expires=$(jq -rRn "$infer" "$transcript" 2>/dev/null)
    fi
  fi
  case $cache_expires in
    ''|*[!0-9]*) cache_expires=na ;;
    *) cache_mark="~" ;;
  esac
fi

if [ "$cache_expires" = na ]; then
  cache_txt="na"
  cache_mark=""
  pcolor='\033[2m'
else
  cache_left=$(( cache_expires - now ))
  if [ "$cache_left" -le 0 ]; then
    cache_txt="cold"
    pcolor='\033[34m'
  else
    if [ "$cache_left" -ge 60 ]; then
      cache_txt="$((cache_left / 60))m"
    else
      cache_txt="${cache_left}s"
    fi
    if [ "$cache_left" -lt 180 ]; then
      pcolor='\033[31m'
    elif [ "$cache_left" -lt 660 ]; then
      pcolor='\033[33m'
    else
      pcolor='\033[2m'
    fi
  fi
fi
cache=" \033[2m|\033[0m ${pcolor}${cache_mark}${cache_txt}\033[0m"

# A yellow "U" when a newer Claude Code is already installed and a restart
# would pick it up. Running the installed version is the normal state and says
# nothing worth the width; an unreadable symlink is not actionable either, so
# both stay hidden. Its presence is the entire signal, so one glyph is enough
# -- the version numbers themselves are one `claude --version` away. Yellow is
# the hue whose meaning already fits: warm, but not now -- restart when
# convenient, never the red that Ctx / Cache use for "act now".
installed_version=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
ver=""
if [ -n "$running_version" ] && [ -n "$installed_version" ] &&
   [ "$installed_version" != "$running_version" ]; then
  ver=" \033[2m|\033[0m \033[33mU\033[0m"
fi

printf '%b\033[1;34m%s\033[0m%b%b \033[2m|\033[0m \033[36m%s\033[0m%b%b%b%b' "$sname" "$path" "$branch" "$agent" "$model" "$eff" "$ctx" "$cache" "$ver"
