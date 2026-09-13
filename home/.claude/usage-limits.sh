#!/bin/sh
# Plan usage windows for the status line, from the claude.ai usage endpoint.
#
# Why. The statusLine payload carries only the five-hour and seven-day
# windows (2.1.270: five_hour, seven_day, spend_limit), while the account's
# per-model weekly windows -- the "Fable" bucket /usage shows -- live only in
# the usage endpoint's limits[] array. This fetches that endpoint the way
# Claude Code does and prints the windows as shell assignments the status
# line (statusline-command.sh, beside this file) evals:
#
#   u_five=7 u_week=4          whole percentages, "" when unknown
#   u_scoped='Fable:6 Opus:31' one "<display_name>:<pct>" per weekly_scoped
#                              row, "" when the endpoint listed none
#   u_stale=1                  the cache is older than two refresh periods:
#                              the last refresh failed (network, an expired
#                              token), so the numbers are a lower bound
#
# Cost. The status line runs every 60s in every session, so the endpoint is
# read through one cache shared by all of them, refreshed in the background
# once it is older than TTL: this script never waits on the network, it
# prints the cache it has (nothing, on the very first run) and returns.
#
#   statusline --> usage-limits.sh --> cache fresh?  --> print
#                                      stale/missing --> print + spawn:
#                                        curl usage endpoint > cache.tmp
#                                        mv cache.tmp cache   (atomic)
#
# Token: the OAuth token Claude Code itself holds, ~/.claude/.credentials.json
# on Linux, the "Claude Code-credentials" keychain item on macOS. No token
# (an API-key login) prints nothing: the gauges are then absent, which is
# what the payload does for the same account. Never printed, never logged.
set -u

TTL=300
cache=${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage.json
url=https://api.anthropic.com/api/oauth/usage

token() {
  if [ -r "$HOME/.claude/.credentials.json" ]; then
    jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json"
  elif command -v security >/dev/null 2>&1; then
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
      jq -r '.claudeAiOauth.accessToken // empty'
  fi
}

# Refresh in the background when the cache is missing or older than TTL.
# `find -mmin` is the portable mtime test (GNU and BSD stat disagree on
# flags). A refresh in flight leaves cache.tmp behind for at most its curl
# timeout, so concurrent sessions may fetch twice; harmless. Every fd is
# redirected, or the status line's stdout pipe would stay open until curl
# returned and the line would render late.
if [ ! -f "$cache" ] || [ -n "$(find "$cache" -mmin "+$((TTL / 60))" 2>/dev/null)" ]; then
  t=$(token)
  if [ -n "$t" ]; then
    mkdir -p "$(dirname "$cache")"
    (
      curl -sf -m 8 -H "Authorization: Bearer $t" -H "anthropic-beta: oauth-2025-04-20" \
        -o "$cache.tmp" "$url" && jq -e '.five_hour' "$cache.tmp" >/dev/null 2>&1 && mv "$cache.tmp" "$cache"
      rm -f "$cache.tmp"
    ) >/dev/null 2>&1 </dev/null &
  fi
fi

[ -f "$cache" ] || exit 0
stale=""
[ -n "$(find "$cache" -mmin "+$((2 * TTL / 60))" 2>/dev/null)" ] && stale=1
jq -r --arg stale "$stale" '
  def pct(f): (f | if . == null then "" else (. | floor | tostring) end);
  @sh "u_five=\(pct(.five_hour.utilization))",
  @sh "u_week=\(pct(.seven_day.utilization))",
  @sh "u_scoped=\([.limits[]? | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
                  | "\(.scope.model.display_name):\(.percent | floor)"] | join(" "))",
  @sh "u_stale=\($stale)"' "$cache" 2>/dev/null
