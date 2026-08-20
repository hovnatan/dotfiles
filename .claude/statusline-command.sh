#!/bin/sh
# Claude Code statusLine: model + effort (blended with PS1-derived cwd/git branch)
# Regenerate/modify this file only via the statusline-setup agent.

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

# Effort rides along with the model in one color run; omitted entirely when
# the payload does not report it, rather than showing a placeholder.
[ -n "$effort" ] && model="$model $effort"

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

# Git branch, yellow if dirty / plain if clean. Dirty is the normal working
# state, so it gets the mild color and red stays reserved for act-now.
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ref=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$ref" ] && ref=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      gcolor='\033[33m'
    else
      gcolor=''
    fi
    branch=" ${gcolor}(${ref})\033[0m"
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
# noticing, so it gets full magenta rather than a dim aside.
agent=""
if [ -n "$agent_name" ]; then
  agent=" \033[35m@${agent_name}\033[0m"
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
# symlink is not actionable either, so both stay hidden.
installed_version=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
ver=""
if [ -n "$running_version" ] && [ -n "$installed_version" ] &&
   [ "$installed_version" != "$running_version" ]; then
  ver=" \033[2m|\033[0m \033[1;31mv${running_version}\033[0m"
fi

printf '%b\033[1;34m%s\033[0m%b%b \033[2m|\033[0m \033[36m%s\033[0m%b%b%b' "$sname" "$path" "$branch" "$agent" "$model" "$ctx" "$rl" "$ver"
