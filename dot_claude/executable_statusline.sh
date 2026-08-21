#!/usr/bin/env bash
# Claude Code status line: current directory (~ shortened) + git branch + plan usage
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
short="${dir/#$HOME/~}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

reset_c=$'\033[0m'

# heat <pct> -> truecolor escape, uniform blue(0%)->green->yellow->red(100%)
heat() {
  awk -v p="$1" 'BEGIN{
    if(p<0)p=0; if(p>100)p=100;
    h=240*(1-p/100);
    hp=h/60; a=hp-2*int(hp/2); d=a-1; if(d<0)d=-d; x=1-d;
    reg=int(hp);
    if(reg==0){r=1;g=x;b=0} else if(reg==1){r=x;g=1;b=0}
    else if(reg==2){r=0;g=1;b=x} else if(reg==3){r=0;g=x;b=1}
    else {r=x;g=0;b=1}
    printf "\033[38;2;%d;%d;%dm", r*255+0.5, g*255+0.5, b*255+0.5;
  }'
}

# Plan usage (Pro/Max): present only after the first API response of a session.
# Each window is coloured by its own usage. 5h shows reset time, 7d reset date.
segs=""
add_seg() { # $1 label  $2 pct  $3 reset_epoch  $4 date-fmt
  [ -z "$2" ] && return
  local p seg rt
  p=$(printf '%.0f' "$2")
  seg="$1 ${p}%"
  rt=$(date -d "@$3" +"$4" 2>/dev/null)
  [ -n "$3" ] && [ -n "$rt" ] && seg="$seg →$rt"
  seg="$(heat "$p")${seg}${reset_c}"
  segs="${segs:+$segs   }$seg"
}

five=$(printf  '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
freset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
week=$(printf  '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
wreset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
add_seg "5h" "$five" "$freset" "%H:%M"
add_seg "7d" "$week" "$wreset" "%-m/%-d"

# Line 1: path + branch (may be truncated). Line 2: usage on its own short row.
line1="$short"
[ -n "$branch" ] && line1="$line1  $branch"
if [ -n "$segs" ]; then
  printf '%s\n%s' "$line1" "$segs"
else
  printf '%s' "$line1"
fi
