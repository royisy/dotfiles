#!/usr/bin/env bash
# Claude Code status line: current directory (~ shortened) + git branch + plan usage
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
short="${dir/#$HOME/~}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)

reset_c=$'\033[0m'

# heat <val0-100> -> truecolor escape, uniform blue(0)->green->yellow->red(100)
heat() {
  awk -v p="$1" 'BEGIN{
    if(p<0)p=0; if(p>100)p=100;
    h=240*(1-p/100);
    hp=h/60; a=hp-2*int(hp/2); d=a-1; if(d<0)d=-d; x=1-d;
    reg=int(hp);
    if(reg==0){r=1;g=x;b=0} else if(reg==1){r=x;g=1;b=0}
    else if(reg==2){r=0;g=1;b=x} else if(reg==3){r=0;g=x;b=1}
    else {r=x;g=0;b=1}
    # Deep blue is too dark to read on a dark background. When blue is the
    # dominant channel, brighten toward CYAN (raise green, drop red) rather
    # than white, so it reads as sky-blue instead of purple. Warm colors keep
    # full saturation so red stays vivid for CRIT.
    lum=0.299*r+0.587*g+0.114*b; floor=0.6;
    if(b>=r && b>=g && lum<floor){
      den=0.587*(1-g)-0.299*r;
      if(den>0){ t=(floor-lum)/den; if(t>1)t=1; if(t<0)t=0; r=r*(1-t); g=g+(1-g)*t }
    }
    printf "\033[38;2;%d;%d;%dm", r*255+0.5, g*255+0.5, b*255+0.5;
  }'
}

# Plan usage (Pro/Max): present only after the first API response of a session.
five=$(printf  '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
freset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
week=$(printf  '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
wreset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

segs=""
append() { segs="${segs:+$segs   }$1"; }         # 3-space separated segments

# Context window usage, coloured by its own level.
if [ -n "$ctx" ]; then
  p=$(printf '%.0f' "$ctx")
  append "$(heat "$p")ctx ${p}%${reset_c}"
fi

# 5-hour window: usage% + reset time + pace badge (fast/slow vs elapsed time).
if [ -n "$five" ]; then
  p=$(printf '%.0f' "$five")
  seg="5h ${p}%"
  rt=$(date -d "@$freset" +%H:%M 2>/dev/null)
  [ -n "$freset" ] && [ -n "$rt" ] && seg="$seg →$rt"
  seg="$(heat "$p")${seg}${reset_c}"
  # Pace = actual usage / usage expected if spent evenly over the 5h window.
  # Window started 5h (18000s) before it resets; skip the noisy first 10 min.
  if [ -n "$freset" ]; then
    now=$(date +%s)
    pace=$(awk -v u="$five" -v fr="$freset" -v now="$now" 'BEGIN{
      el=now-(fr-18000); if(el<600)exit;
      f=el/18000; if(f>1)f=1; e=f*100; if(e<=0)exit;
      printf "%.2f", u/e }')
    if [ -n "$pace" ]; then
      lab=$(awk -v p="$pace" 'BEGIN{print (p>=1.5)?"CRIT":(p>=1.1)?"WARN":"OK"}')
      hv=$(awk -v p="$pace" 'BEGIN{v=(p-0.5)*100; if(v<0)v=0; if(v>100)v=100; print v}')
      seg="$seg $(heat "$hv")${lab}${reset_c}"
    fi
  fi
  append "$seg"
fi

# 7-day window: usage% + reset date.
if [ -n "$week" ]; then
  p=$(printf '%.0f' "$week")
  seg="7d ${p}%"
  rt=$(date -d "@$wreset" +'%-m/%-d' 2>/dev/null)
  [ -n "$wreset" ] && [ -n "$rt" ] && seg="$seg →$rt"
  append "$(heat "$p")${seg}${reset_c}"
fi

# Line 1: path + branch (with "*" when the working tree is dirty).
dirty=""
[ -n "$branch" ] && [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] && dirty="*"
line1="$short"
[ -n "$branch" ] && line1="$line1  ${branch}${dirty}"

# Line 2: model + usage segments.
line2="$model"
[ -n "$segs" ] && line2="${line2:+$line2   }$segs"

if [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  printf '%s' "$line1"
fi
