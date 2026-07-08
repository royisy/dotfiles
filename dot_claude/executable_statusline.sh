#!/usr/bin/env bash
# Claude Code status line: current directory (~ shortened) + git branch
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
short="${dir/#$HOME/~}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  printf '%s  %s' "$short" "$branch"
else
  printf '%s' "$short"
fi
