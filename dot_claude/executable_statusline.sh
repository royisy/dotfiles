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
now=$(date +%s)

# pace_badge <pace> -> " <colored OK|WARN|CRIT>" (empty if pace empty).
# Standard traffic-light / Nagios palette: OK=green, WARN=yellow, CRIT=red.
pace_badge() {
  [ -z "$1" ] && return
  local lab hv
  lab=$(awk -v p="$1" 'BEGIN{print (p>=1.5)?"CRIT":(p>=1.1)?"WARN":"OK"}')
  case "$lab" in
    OK)   hv=45 ;;
    WARN) hv=75 ;;
    CRIT) hv=100 ;;
  esac
  printf ' %s%s%s' "$(heat "$hv")" "$lab" "$reset_c"
}

segs=""
append() { segs="${segs:+$segs   }$1"; }         # 3-space separated segments

# Context window usage, coloured by its own level.
if [ -n "$ctx" ]; then
  p=$(printf '%.0f' "$ctx")
  append "$(heat "$p")ctx ${p}%${reset_c}"
fi

# 5-hour window: usage% + reset time + time left + pace badge.
if [ -n "$five" ]; then
  p=$(printf '%.0f' "$five")
  seg="5h ${p}%"
  if [ -n "$freset" ]; then
    rt=$(date -d "@$freset" +%H:%M 2>/dev/null)
    [ -n "$rt" ] && seg="$seg →$rt"
    rem=$(( freset - now ))
    [ "$rem" -gt 0 ] && seg="$seg ($(awk -v s="$rem" 'BEGIN{h=int(s/3600);m=int((s%3600)/60); if(h>0)printf "%dh%02dm",h,m; else printf "%dm",m}'))"
  fi
  seg="$(heat "$p")${seg}${reset_c}"
  # Pace = actual usage / usage expected if spent evenly over the 5h window.
  # Window started 5h (18000s) before it resets; skip the noisy first 10 min.
  if [ -n "$freset" ]; then
    pace=$(awk -v u="$five" -v fr="$freset" -v now="$now" 'BEGIN{
      el=now-(fr-18000); if(el<600)exit;
      f=el/18000; if(f>1)f=1; e=f*100; if(e<=0)exit;
      printf "%.2f", u/e }')
    seg="$seg$(pace_badge "$pace")"
  fi
  append "$seg"
fi

# 7-day window: usage% + reset date + pace badge.
# Budget is meant to last 5 working days (Mon-Fri); any 7-day window contains
# exactly 5 weekdays. Expected usage = elapsed working days / 5. Weekends do
# not add to the expected burn, so 1 working day used should sit near 20%.
if [ -n "$week" ]; then
  p=$(printf '%.0f' "$week")
  seg="7d ${p}%"
  if [ -n "$wreset" ]; then
    rt=$(date -d "@$wreset" +'%-m/%-d' 2>/dev/null)
    [ -n "$rt" ] && seg="$seg →$rt"
  fi
  seg="$(heat "$p")${seg}${reset_c}"
  if [ -n "$wreset" ]; then
    ws=$(( wreset - 604800 ))                 # window start = reset - 7 days
    # Sum weekday seconds inside [ws, now], counting each CALENDAR day by its
    # own weekday (aligned to local midnight, not the window's start time).
    work=0
    cur=$(date -d "$(date -d "@$ws" +%Y-%m-%d) 00:00:00" +%s 2>/dev/null)
    while [ -n "$cur" ] && [ "$cur" -lt "$now" ]; do
      nxt=$(( cur + 86400 ))
      s=$cur; [ "$ws"  -gt "$s" ] && s=$ws     # clip to window start
      e=$nxt; [ "$now" -lt "$e" ] && e=$now    # clip to now
      if [ "$e" -gt "$s" ] && [ "$(date -d "@$cur" +%u 2>/dev/null)" -le 5 ]; then
        work=$(( work + e - s ))
      fi
      cur=$nxt
    done
    pace=$(awk -v u="$week" -v work="$work" 'BEGIN{
      wd=work/86400; if(wd<0.1)exit;          # working days elapsed; skip if <~2.4h
      e=wd/5*100; if(e<=0)exit;               # expected % (5 working days = 100%)
      printf "%.2f", u/e }')
    seg="$seg$(pace_badge "$pace")"
  fi
  append "$seg"
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
