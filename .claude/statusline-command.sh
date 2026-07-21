#!/bin/sh
# Claude Code statusLine: model + effort (blended with PS1-derived cwd/git branch)
# Regenerate/modify this file only via the statusline-setup agent.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
effort=$(echo "$input" | jq -r '.effort.level // "n/a"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Abbreviate $HOME to ~ (from PS1's path_abbrev)
case "$cwd" in
  "$HOME"*) path="~${cwd#$HOME}" ;;
  *) path="$cwd" ;;
esac

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

printf '\033[1;34m%s\033[0m%b \033[2m|\033[0m \033[36m%s\033[0m \033[2m[%s]\033[0m%b' "$path" "$branch" "$model" "$effort" "$ctx"
