#!/bin/sh
# Claude Code statusLine: model + effort (blended with PS1-derived cwd/git branch)
# Regenerate/modify this file only via the statusline-setup agent.
#
# Hue budget -- one meaning per color, so nothing on the line reads two ways.
# Adding an element? Take a free treatment, or share one whose meaning already
# matches; never re-use a hue for an unrelated idea.
#
#   bold blue      path                    matches the PS1 in ~/.zshrc.shared
#   green          branch                  matches that PS1; "*" marks dirty
#   yellow         gauge 50-80%            warm, but not now
#   red            gauge >=80%             act now -- nothing else, ever
#   cyan           model
#   bold magenta   @agent                  rare, so it gets the loud hue
#   weight only    effort ramp             2m / plain / 1m / 1;4m / 1;7m
#   dim            separators
#   plain          version note            present = the signal; no hue needed
#
# Clean/dirty is a binary, so it is a glyph rather than a hue. Yellow was the
# obvious candidate and it does not work: GitLab Light has to darken yellow to
# be legible on #fafaff, landing on #af551d -- dE 23.6 from its own red -- so a
# dirty tree read as an error at a glance. No other hue separates either (the
# best, cyan at dE 50.5, is the model's and points the wrong way semantically).
# A trailing "*" costs one column and is exact in any theme, at any size, and
# colorblind. It is also what git's own __git_ps1 uses.

input=$(cat)

model_id=$(echo "$input" | jq -r '.model.id')
model=$(echo "$input" | jq -r '.model.display_name' | sed -E 's/ \(1M context\)$//')
case "$model_id" in
  *"[1m]"*) model="$model [1m]" ;;
esac
effort=$(echo "$input" | jq -r '.effort.level // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
rl_five_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
running_version=$(echo "$input" | jq -r '.version // empty')

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
eff=""
if [ -n "$effort" ]; then
  case "$effort" in
    low) ecolor='\033[2m' ;;
    medium) ecolor='' ;;
    high) ecolor='\033[1m' ;;
    xhigh) ecolor='\033[1;4m' ;;
    max) ecolor='\033[1;7m' ;;
    *) ecolor='' ;;
  esac
  eff=" ${ecolor}${effort}\033[0m"
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
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ref=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$ref" ] && ref=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    dirty=""
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      dirty="*"
    fi
    branch=" \033[32m(${ref}${dirty})\033[0m"
  fi
fi

# Session name (set via -n or /rename; absent on unnamed sessions), shown
# whole -- including the "<hostname>-" prefix these sessions are named with
# (see ~/.dotfiles/scripts/claude_tmux_run.sh) -- and trimmed to at most 20
# characters (17 + "...") to keep the line short.
sname=""
if [ -n "$session_name" ]; then
  if [ "${#session_name}" -gt 20 ]; then
    session_name="$(printf '%.17s' "$session_name")..."
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
  ctx=" \033[2m|\033[0m ${ccolor}Ctx ${ctx_pct}%\033[0m"
fi

# Claude.ai rate-limit utilization (five_hour / seven_day independently optional),
# each dim/yellow/red by the same thresholds as Ctx above
rl_parts=""
if [ -n "$rl_five_used" ]; then
  five_pct=$(printf '%.0f' "$rl_five_used")
  if [ "$five_pct" -ge 80 ]; then
    fcolor='\033[31m'
  elif [ "$five_pct" -ge 50 ]; then
    fcolor='\033[33m'
  else
    fcolor='\033[2m'
  fi
  rl_parts="${fcolor}5h ${five_pct}%\033[0m"
fi
if [ -n "$rl_week_used" ]; then
  week_pct=$(printf '%.0f' "$rl_week_used")
  if [ "$week_pct" -ge 80 ]; then
    wcolor='\033[31m'
  elif [ "$week_pct" -ge 50 ]; then
    wcolor='\033[33m'
  else
    wcolor='\033[2m'
  fi
  if [ -n "$rl_parts" ]; then
    rl_parts="${rl_parts} \033[2m.\033[0m ${wcolor}7d ${week_pct}%\033[0m"
  else
    rl_parts="${wcolor}7d ${week_pct}%\033[0m"
  fi
fi
rl=""
if [ -n "$rl_parts" ]; then
  rl=" \033[2m|\033[0m ${rl_parts}"
fi

# Currently running Claude Code version, shown only when a newer one is
# already installed and a restart would pick it up. Running the installed
# version is the normal state and says nothing worth the width; an unreadable
# symlink is not actionable either, so both stay hidden. Uncolored on purpose:
# it only appears when it is true, so its presence is the entire signal, and a
# restart-when-convenient note must not wear the red that Ctx / 5h / 7d use.
installed_version=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
ver=""
if [ -n "$running_version" ] && [ -n "$installed_version" ] &&
   [ "$installed_version" != "$running_version" ]; then
  ver=" \033[2m|\033[0m v${running_version}"
fi

printf '%b\033[1;34m%s\033[0m%b%b \033[2m|\033[0m \033[36m%s\033[0m%b%b%b%b' "$sname" "$path" "$branch" "$agent" "$model" "$eff" "$ctx" "$rl" "$ver"
