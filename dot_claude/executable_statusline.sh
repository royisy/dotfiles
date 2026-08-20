#!/usr/bin/env bash
# Claude Code status line: current directory (~ shortened) + git branch + plan usage
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
short="${dir/#$HOME/~}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

# Plan usage (Pro/Max): present only after the first API response of a session.
# Show 5-hour window usage and when that window resets (local time).
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
usage=""
if [ -n "$five" ]; then
  usage="5h $(printf '%.0f' "$five")%"
  rt=$(date -d "@$reset" +%H:%M 2>/dev/null)
  [ -n "$reset" ] && [ -n "$rt" ] && usage="$usage →$rt"
fi

orange=$'\033[38;5;208m'
reset_c=$'\033[0m'
out="$short"
[ -n "$branch" ] && out="$out  $branch"
[ -n "$usage" ] && out="$out  ·  ${orange}${usage}${reset_c}"
printf '%s' "$out"
