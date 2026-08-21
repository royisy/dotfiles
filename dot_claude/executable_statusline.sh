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
  pct=$(printf '%.0f' "$five")
  usage="5h ${pct}%"
  rt=$(date -d "@$reset" +%H:%M 2>/dev/null)
  [ -n "$reset" ] && [ -n "$rt" ] && usage="$usage →$rt"

  # Heat color by usage, uniform across 0..100%: blue -> green -> yellow -> red.
  # HSV hue 240..0 mapped to a truecolor escape.
  esc=$(awk -v p="$pct" 'BEGIN{
    if(p<0)p=0; if(p>100)p=100;
    h = 240*(1-p/100);
    hp=h/60; a=hp-2*int(hp/2); d=a-1; if(d<0)d=-d; x=1-d;
    reg=int(hp);
    if(reg==0){r=1;g=x;b=0} else if(reg==1){r=x;g=1;b=0}
    else if(reg==2){r=0;g=1;b=x} else if(reg==3){r=0;g=x;b=1}
    else {r=x;g=0;b=1}
    printf "\033[38;2;%d;%d;%dm", r*255+0.5, g*255+0.5, b*255+0.5;
  }')
fi

reset_c=$'\033[0m'
out="$short"
[ -n "$branch" ] && out="$out  $branch"
[ -n "$usage" ] && out="$out  ·  ${esc}${usage}${reset_c}"
printf '%s' "$out"
