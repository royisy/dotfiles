#!/usr/bin/env bash
# Claude Code status line: current directory (~ shortened) + git branch + plan usage
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
short="${dir/#$HOME/~}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

# Plan usage (Pro/Max): present only after the first API response of a session
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
usage=""
[ -n "$five" ] && usage="5h $(printf '%.0f' "$five")%"
[ -n "$week" ] && usage="${usage:+$usage  }7d $(printf '%.0f' "$week")%"

out="$short"
[ -n "$branch" ] && out="$out  $branch"
[ -n "$usage" ] && out="$out  ·  $usage"
printf '%s' "$out"
