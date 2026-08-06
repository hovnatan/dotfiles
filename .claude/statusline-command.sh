#!/bin/sh
# Claude Code statusLine: model + effort (blended with PS1-derived cwd/git branch)
# Regenerate/modify this file only via the statusline-setup agent.

input=$(cat)

model_id=$(echo "$input" | jq -r '.model.id')
model=$(echo "$input" | jq -r '.model.display_name' | sed -E 's/ \(1M context\)$//')
case "$model_id" in
  *"[1m]"*) model="$model [1m]" ;;
esac
effort=$(echo "$input" | jq -r '.effort.level // "n/a"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
rl_five_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
running_version=$(echo "$input" | jq -r '.version // empty')

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

# Git branch, colored red if dirty / green if clean (from PS1's git_prompt_status/git_prompt_info)
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ref=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$ref" ] && ref=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      gcolor='\033[31m'
    else
      gcolor='\033[32m'
    fi
    branch=" ${gcolor}(${ref})\033[0m"
  fi
fi

# Session name (set via -n or /rename; absent on unnamed sessions)
sname=""
if [ -n "$session_name" ]; then
  sname="\033[2m${session_name}\033[0m "
fi

# Main-thread agent name (absent unless the session is running as a custom
# agent type via --agent / a .claude/agents/*.md slug)
agent=""
if [ -n "$agent_name" ]; then
  agent=" \033[2;35m@${agent_name}\033[0m"
fi

# Context window usage, colored green/yellow/red by fullness (absent until first API response)
ctx=""
if [ -n "$ctx_used" ]; then
  ctx_pct=$(printf '%.0f' "$ctx_used")
  if [ "$ctx_pct" -ge 80 ]; then
    ccolor='\033[31m'
  elif [ "$ctx_pct" -ge 50 ]; then
    ccolor='\033[33m'
  else
    ccolor='\033[32m'
  fi
  ctx=" \033[2m|\033[0m ${ccolor}Ctx ${ctx_pct}%\033[0m"
fi

# Claude.ai rate-limit utilization (five_hour / seven_day independently optional),
# each colored green/yellow/red by the same thresholds as Ctx above
rl_parts=""
if [ -n "$rl_five_used" ]; then
  five_pct=$(printf '%.0f' "$rl_five_used")
  if [ "$five_pct" -ge 80 ]; then
    fcolor='\033[31m'
  elif [ "$five_pct" -ge 50 ]; then
    fcolor='\033[33m'
  else
    fcolor='\033[32m'
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
    wcolor='\033[32m'
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

# Currently running Claude Code version. Red when a newer version is installed
# (a restart would pick it up); dim otherwise.
installed_version=$(basename "$(readlink "$HOME/.local/bin/claude" 2>/dev/null)" 2>/dev/null)
ver=""
if [ -n "$running_version" ]; then
  if [ -n "$installed_version" ] && [ "$installed_version" != "$running_version" ]; then
    vcolor='\033[1;31m'
  else
    vcolor='\033[2m'
  fi
  ver=" \033[2m|\033[0m ${vcolor}v${running_version}\033[0m"
fi

printf '%b\033[1;34m%s\033[0m%b%b \033[2m|\033[0m \033[36m%s\033[0m \033[2m[%s]\033[0m%b%b%b' "$sname" "$path" "$branch" "$agent" "$model" "$effort" "$ctx" "$rl" "$ver"
