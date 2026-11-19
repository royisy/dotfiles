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

# heat <val0-100> -> truecolor escape along Claude Code's own dark-theme palette:
# permission/rate_limit_fill periwinkle (what /usage fills its bars with) -> success
# -> warning -> error. These are the colours the rest of the UI already uses, so the
# status line sits at the same muted brightness as "auto mode on" instead of the
# neon full-saturation ramp it had before. Stops are placed at the pace_badge
# levels (45/75/100), so a badge lands exactly on success/warning/error.
STOPS="0,177,185,249 45,78,186,101 75,255,193,7 100,255,107,128"
heat() {
  awk -v p="$1" -v stops="$STOPS" 'BEGIN{
    if(p<0)p=0; if(p>100)p=100;
    n=split(stops, st, " ");
    for(i=1;i<=n;i++){ split(st[i], f, ","); pos[i]=f[1]; R[i]=f[2]; G[i]=f[3]; B[i]=f[4] }
    k=1; while(k<n-1 && p>pos[k+1]) k++;
    span=pos[k+1]-pos[k]; t=(span>0)?(p-pos[k])/span:0; if(t>1)t=1;
    printf "\033[38;2;%d;%d;%dm", R[k]+(R[k+1]-R[k])*t+0.5, G[k]+(G[k+1]-G[k])*t+0.5, B[k]+(B[k+1]-B[k])*t+0.5;
  }'
}

now=$(date +%s)

# Plan usage (Pro/Max/Ultra): rate_limits are built from the rate-limit headers of
# the last API response THIS CLI process saw and are held in memory per
# process, so an idle session serves an old snapshot and a process that has
# been told nothing at all carries no rate_limits. Usage is per-account, so
# merge stdin with a shared cache and keep the FRESHER snapshot.
#
# five_hour is the clock. Both windows of a payload are read out of one and
# the same header set, so they are exactly as old as each other, and 5h usage
# only grows inside its window: the payload with the higher five_hour is the
# later reading, and one whose 5h window has already expired predates the
# current window entirely. Rank whole snapshots that way and take seven_day
# off the winner rather than judging it on its own.
#
# The ranking is what matters, because seven_day does NOT only grow. Measured
# across 15 sessions rendering at one instant: 12% wherever five_hour was
# current, and 15/23/29/30/39/42% in sessions whose five_hour had expired -
# the weekly figure decays as old usage ages out of it, so a stale snapshot
# OVERSTATES it. "Take the larger" and "take whoever wrote last" both pin the
# display to whichever idle session happened to render.
#
# An earlier version ranked by the transcript's mtime instead, on the
# assumption that rate_limits only move when an API response arrives. They do
# not - Claude Code re-probes the quota in the background, without writing a
# transcript - so a session holding the correct numbers was demoted for
# looking idle and the stale cache won. That is how 5h read 55% while the
# account was in fact rate-limited at 100%, and 7d read 30% against a true 10%.
CACHE="$HOME/.claude/statusline-usage-cache.json"
cache=$(cat "$CACHE" 2>/dev/null)

# Usage is per account, so is the cache: after switching accounts, the old
# account's live 5h window outranked every reading of the new one until it ran
# out. A cache written for another account (or before this field existed) is
# not ours to serve.
acct=$(jq -r '.oauthAccount.accountUuid // empty' "$HOME/.claude.json" 2>/dev/null)
{ read -r c_acct; read -r acct_since; } <<EOF
$(printf '%s' "$cache" | jq -r '.account, .account_since | if . == null then "" else tostring end' 2>/dev/null)
EOF
[ "$c_acct" = "$acct" ] || { cache=""; acct_since=""; }
[ -n "$acct_since" ] || acct_since=$now

# read4 <json> <jq-prefix> -> R1..R4: 5h used, 5h reset, 7d used, 7d reset
# ("" for anything absent). One jq per source instead of one per field.
read4() {
  R1=""; R2=""; R3=""; R4=""
  { read -r R1; read -r R2; read -r R3; read -r R4; } <<EOF
$(printf '%s' "$1" | jq -r "[$2.five_hour.used_percentage, $2.five_hour.resets_at, $2.seven_day.used_percentage, $2.seven_day.resets_at] | .[] | if . == null then \"\" else tostring end" 2>/dev/null)
EOF
}

read4 "$input" '(.rate_limits // {})'; s_fu="$R1"; s_fr="${R2%.*}"; s_wu="$R3"; s_wr="${R4%.*}"
# A session resumed from before the account switch serves the OLD account's
# rate_limits, restored with its transcript, until it next talks to the API:
# after one switch, three such sessions offered a 7d window that outlived the
# new account's, which outranked it below. A transcript untouched since this
# account was first seen cannot hold a reading of it.
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$transcript" ] && [ -f "$transcript" ] && [ "$(stat -c %Y "$transcript" 2>/dev/null || echo "$now")" -lt "$acct_since" ]; then
  s_fu=""; s_fr=""; s_wu=""; s_wr=""
fi
read4 "$cache" '(. // {})';            c_fu="$R1"; c_fr="${R2%.*}"; c_wu="$R3"; c_wr="${R4%.*}"
{ read -r c_seen; read -r c_day; read -r c_day_wr; read -r c_day_base; } <<EOF
$(printf '%s' "$cache" | jq -r '(.seen_at // .updated_at), .day.date, .day.wreset, .day.base | if . == null then "" else tostring end' 2>/dev/null)
EOF
c_seen="${c_seen%.*}"; case "$c_seen" in ''|*[!0-9]*) c_seen=0 ;; esac
# The last 7d reading, kept before the expiry check below can drop it: at the
# first render of a day it is where the day starts from.
prev_wu="$c_wu"; prev_wr="$c_wr"

# A window needs BOTH numbers to be usable. A resets_at without a usage figure
# would otherwise win the ranking below, hide the segment, and get persisted as
# a fabricated 0.
[ -z "$s_fu" ] && s_fr=""; [ -z "$s_fr" ] && s_fu=""
[ -z "$s_wu" ] && s_wr=""; [ -z "$s_wr" ] && s_wu=""
[ -z "$c_fu" ] && c_fr=""; [ -z "$c_fr" ] && c_fu=""
[ -z "$c_wu" ] && c_wr=""; [ -z "$c_wr" ] && c_wu=""

# An expired window is over, not stale: drop it. Only the 7d rollover is worth
# remembering - an absent 5h window is displayed as 0 either way.
wrolled=""
[ -n "$s_fr" ] && [ "$s_fr" -le "$now" ] && { s_fu=""; s_fr=""; }
[ -n "$c_fr" ] && [ "$c_fr" -le "$now" ] && { c_fu=""; c_fr=""; }
[ -n "$s_wr" ] && [ "$s_wr" -le "$now" ] && { s_wu=""; s_wr=""; wrolled=1; }
[ -n "$c_wr" ] && [ "$c_wr" -le "$now" ] && { c_wu=""; c_wr=""; wrolled=1; }

# Rank by the five_hour clock: a live 5h window beats an expired or absent one,
# a later window beats an earlier one, and inside one window more usage means a
# later reading. Ties go to stdin - that one we know we are reading right now.
winner=stdin
if [ -n "$c_fr" ]; then
  if [ -z "$s_fr" ] || [ "$c_fr" -gt "$s_fr" ]; then winner=cache
  elif [ "$c_fr" -eq "$s_fr" ] && awk -v a="$c_fu" -v b="$s_fu" 'BEGIN{exit !(a>b)}'; then winner=cache
  fi
elif [ -z "$s_fr" ] && [ -n "$c_wr" ]; then
  # Neither side holds a live 5h window: between windows, or always on a plan
  # without one (a verified Ultra account). seven_day is then the only clock,
  # ranked the same way: a later window beats an earlier one and, inside one,
  # the higher reading is the later. Its resets_at stays put for the whole week
  # (one value from 11/16 to 11/19), so usage inside a window only grows.
  #
  # This used to hand the win to the cache outright, as the last thing ANY
  # session observed beats an idle process (measured during one gap: sixteen
  # idle sessions offering 4-39% for the same 7d window). That relied on the
  # next live 5h window to overwrite it - with no 5h window ever, 7d froze at
  # the first reading.
  if [ -z "$s_wr" ] || [ "$c_wr" -gt "$s_wr" ]; then winner=cache
  elif [ "$c_wr" -eq "$s_wr" ] && awk -v a="$c_wu" -v b="$s_wu" 'BEGIN{exit !(a>b)}'; then winner=cache
  fi
fi

if [ "$winner" = cache ]; then
  five="$c_fu"; freset="$c_fr"; week="$c_wu"; wreset="$c_wr"; seen="$c_seen"
  [ -z "$wreset" ] && { week="$s_wu"; wreset="$s_wr"; }   # winner says nothing about 7d
else
  five="$s_fu"; freset="$s_fr"; week="$s_wu"; wreset="$s_wr"; seen="$now"
  [ -z "$wreset" ] && { week="$c_wu"; wreset="$c_wr"; seen="$c_seen"; }
fi

# Where today started in the 7d window: the last reading from before local
# midnight, carried in the cache across the day. 0 when the window rolled over
# - overnight or during the day - since everything in the new window is today's.
today=$(date +%F)
day_base=""
if [ -n "$wreset" ]; then
  if [ "$c_day" = "$today" ] && [ "$c_day_wr" = "$wreset" ]; then day_base="$c_day_base"
  elif [ "$c_day" != "$today" ] && [ "$prev_wr" = "$wreset" ]; then day_base="${prev_wu:-$week}"
  else day_base=0
  fi
fi

# Persist the snapshot for sessions whose process holds no rate_limits yet.
# Nothing ages it out on a clock: an entry leaves only when its own window
# expires, or when a session holding a live 5h window replaces it. seen_at
# records the age of the READING rather than of this write, so it stays
# honest about what is being served while it is copied from session to
# session.
if [ -n "$freset$wreset" ]; then
  fh=null; sd=null; dy=null
  [ -n "$freset" ] && fh=$(printf '{"used_percentage":%s,"resets_at":%s}' "$five" "$freset")
  [ -n "$wreset" ] && sd=$(printf '{"used_percentage":%s,"resets_at":%s}' "$week" "$wreset")
  [ -n "$day_base" ] && dy=$(printf '{"date":"%s","wreset":%s,"base":%s}' "$today" "$wreset" "$day_base")
  tmp=$(mktemp "$HOME/.claude/.usage-cache.XXXXXX" 2>/dev/null) && {
    printf '{"account":"%s","account_since":%s,"five_hour":%s,"seven_day":%s,"day":%s,"seen_at":%s}\n' "$acct" "$acct_since" "$fh" "$sd" "$dy" "$seen" > "$tmp" 2>/dev/null \
      && mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  }
fi

# Without a live 5h window - between windows, or on a plan that has none -
# the 5h slot shows today's share of the week instead (see below), so the row
# keeps its shape either way.
#
# An absent seven_day means "never heard", not "zero": its window is a week
# long and running essentially always - unless we watched the window expire,
# which is the one case where 0 is a fact. Persistence above is deliberately
# untouched: a level with no boundary is nothing to hand other sessions.
[ -z "$week" ] && [ -n "$wrolled" ] && week=0

# pace_badge <pace> <used%> -> " <colored OK|WARN|CRIT>".
# Severity is the WORSE of two signals: the pace trajectory (burning faster
# than the window can sustain) and having actually run out.
# OK=success, WARN=warning, CRIT=error - Claude Code's own semantic colours,
# reached through heat() at the ramp stops that carry them.
#
# The level signal used to be a flat (u>=95)?CRIT:(u>=85)?WARN floor, to keep a
# near-full window from reading OK on good pacing. It cannot see the clock, so
# it fired at the END of a window too, where being near the ceiling costs
# nothing because the reset arrives first: 89% with five minutes left read WARN
# while the pace was 0.91. The time axis is already in the pace (expected usage
# grows with the elapsed window), so the floor was redundant everywhere except
# at exhaustion - 95% mid-window is pace 1.9 = CRIT on its own. What pace cannot
# express is being blocked right now, so that is all the level signal says now.
pace_badge() {
  local pace="$1" used="$2" ps=0 ls=0 sev lab hv
  [ -n "$pace" ] && ps=$(awk -v p="$pace" 'BEGIN{print (p>=1.5)?2:(p>=1.1)?1:0}')
  [ -n "$used" ] && ls=$(awk -v u="$used" 'BEGIN{print (u>=99)?2:0}')
  # Nothing to show: no pace signal (too early) and not out of budget.
  [ -z "$pace" ] && [ "$ls" -eq 0 ] && return
  sev=$ps; [ "$ls" -gt "$sev" ] && sev=$ls
  case "$sev" in
    0) lab=OK;   hv=45  ;;
    1) lab=WARN; hv=75  ;;
    2) lab=CRIT; hv=100 ;;
  esac
  printf ' %s%s%s' "$(heat "$hv")" "$lab" "$reset_c"
}

segs=""
append() { segs="${segs:+$segs   }$1"; }         # 3-space separated segments

# Only the values carry colour (usage % and the badge); labels, reset times and
# time-remaining stay in the status line's default grey so the eye lands on the
# numbers rather than on whole coloured phrases.

# Context window usage, coloured by its own level.
if [ -n "$ctx" ]; then
  p=$(printf '%.0f' "$ctx")
  append "ctx $(heat "$p")${p}%${reset_c}"
fi

# 5-hour window: usage% + reset time + time left + pace badge.
if [ -n "$freset" ]; then
  p=$(printf '%.0f' "$five")
  seg="5h $(heat "$p")${p}%${reset_c}"
  if [ -n "$freset" ]; then
    rt=$(date -d "@$freset" +%H:%M 2>/dev/null)
    [ -n "$rt" ] && seg="$seg ->$rt"
    rem=$(( freset - now ))
    [ "$rem" -gt 0 ] && seg="$seg ($(awk -v s="$rem" 'BEGIN{h=int(s/3600);m=int((s%3600)/60); if(h>0)printf "%dh%02dm",h,m; else printf "%dm",m}'))"
  fi
  # Pace = actual usage / usage expected if spent evenly over the 5h window.
  # Window started 5h (18000s) before it resets; skip the noisy first 10 min.
  pace=""
  if [ -n "$freset" ]; then
    pace=$(awk -v u="$five" -v fr="$freset" -v now="$now" 'BEGIN{
      el=now-(fr-18000); if(el<600)exit;
      f=el/18000; if(f>1)f=1; e=f*100; if(e<=0)exit;
      printf "%.2f", u/e }')
  fi
  seg="$seg$(pace_badge "$pace" "$five")"
  append "$seg"

# No 5h window: today's usage against today's share of the week. The share is
# the week left at the start of the day spread over the weekdays left before
# the reset day, today included - the reset day's morning belongs to the next
# window's budget, so on that day the leftover is all today's. It is worked out
# afresh every day, so a heavy day shrinks the days after it and a light one
# grows them. Days run from local midnight, which no working day crosses.
# Only the % is shown: the share itself is fixed for the day, so it says
# nothing new once the day has started. Weekends have no share; they show the
# plain weekly % used ("of week") and come out of the following weekdays' shares.
elif [ -n "$day_base" ]; then
  used=$(awk -v w="$week" -v b="$day_base" 'BEGIN{d=w-b; if(d<0)d=0; printf "%.0f", d}')
  if [ "$(date +%u)" -le 5 ]; then
    left=0; d="$today"; rd=$(date -d "@$wreset" +%F)
    while [[ "$d" < "$rd" ]]; do
      [ "$(date -d "$d" +%u)" -le 5 ] && left=$(( left + 1 ))
      d=$(date -d "$d +1 day" +%F)
    done
    [ "$left" -eq 0 ] && left=1
    p=$(awk -v w="$week" -v b="$day_base" -v n="$left" 'BEGIN{
      s=(100-b)/n; d=w-b; if(d<0)d=0;
      printf "%.0f", (s>0)?d/s*100:100 }')
    append "today $(heat "$p")${p}%${reset_c}"
  else
    append "today ${used}% of week"
  fi
fi

# 7-day window: usage% + reset date + pace badge.
# Budget is meant to last 5 working days (Mon-Fri); any 7-day window contains
# exactly 5 weekdays. Expected usage = working days begun / 5: a weekday counts
# whole from its first minute, so on day one anything up to 20% is on pace,
# whatever the hour. Weekends do not add to the expected burn.
#
# This used to count weekday SECONDS, as if a day's share were spent evenly over
# its 24 hours: 8% at 18:46 on the window's first day read WARN (0.37 days in,
# 7.3% "expected"), though a working day is not 24 hours long and when it starts
# varies - the same reason today's share has no pace of its own.
if [ -n "$week" ]; then
  p=$(printf '%.0f' "$week")
  seg="week $(heat "$p")${p}%${reset_c}"
  if [ -n "$wreset" ]; then
    rt=$(date -d "@$wreset" +'%-m/%-d' 2>/dev/null)
    [ -n "$rt" ] && seg="$seg ->$rt"
  fi
  pace=""
  if [ -n "$wreset" ]; then
    # Weekdays begun inside the window, counting each CALENDAR day from the
    # window's start (reset - 7 days) through today by its own weekday.
    wd=0; d=$(date -d "@$(( wreset - 604800 ))" +%F 2>/dev/null)
    while [ -n "$d" ] && ! [[ "$d" > "$today" ]]; do
      [ "$(date -d "$d" +%u)" -le 5 ] && wd=$(( wd + 1 ))
      d=$(date -d "$d +1 day" +%F)
    done
    pace=$(awk -v u="$week" -v wd="$wd" 'BEGIN{
      if(wd<1)exit; if(wd>5)wd=5;             # the reset morning makes a 6th
      printf "%.2f", u/(wd/5*100) }')
  fi
  seg="$seg$(pace_badge "$pace" "$week")"
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
