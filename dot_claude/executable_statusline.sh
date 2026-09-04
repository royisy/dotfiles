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

# Plan usage (Pro/Max): rate_limits are built from the rate-limit headers of
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

# read4 <json> <jq-prefix> -> R1..R4: 5h used, 5h reset, 7d used, 7d reset
# ("" for anything absent). One jq per source instead of one per field.
read4() {
  R1=""; R2=""; R3=""; R4=""
  { read -r R1; read -r R2; read -r R3; read -r R4; } <<EOF
$(printf '%s' "$1" | jq -r "[$2.five_hour.used_percentage, $2.five_hour.resets_at, $2.seven_day.used_percentage, $2.seven_day.resets_at] | .[] | if . == null then \"\" else tostring end" 2>/dev/null)
EOF
}

read4 "$input" '(.rate_limits // {})'; s_fu="$R1"; s_fr="${R2%.*}"; s_wu="$R3"; s_wr="${R4%.*}"
read4 "$cache" '(. // {})';            c_fu="$R1"; c_fr="${R2%.*}"; c_wu="$R3"; c_wr="${R4%.*}"
c_seen=$(printf '%s' "$cache" | jq -r '.seen_at // .updated_at // empty' 2>/dev/null)
c_seen="${c_seen%.*}"; case "$c_seen" in ''|*[!0-9]*) c_seen=0 ;; esac

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
  # Neither side can be dated - between 5h windows nobody holds one. The cache
  # is then the better guess: it is the last thing ANY session on this machine
  # observed, while an idle process is a lottery (measured during one gap:
  # sixteen idle sessions offering 4/11/18/19/21/23/28/29/30/32/34/37/39% for
  # the same 7d window). It cannot get stuck there - the next session to hold a
  # live 5h window outranks it and overwrites it.
  winner=cache
fi

if [ "$winner" = cache ]; then
  five="$c_fu"; freset="$c_fr"; week="$c_wu"; wreset="$c_wr"; seen="$c_seen"
  [ -z "$wreset" ] && { week="$s_wu"; wreset="$s_wr"; }   # winner says nothing about 7d
else
  five="$s_fu"; freset="$s_fr"; week="$s_wu"; wreset="$s_wr"; seen="$now"
  [ -z "$wreset" ] && { week="$c_wu"; wreset="$c_wr"; seen="$c_seen"; }
fi

# Persist the snapshot for sessions whose process holds no rate_limits yet.
# Nothing ages it out on a clock: an entry leaves only when its own window
# expires, or when a session holding a live 5h window replaces it. seen_at
# records the age of the READING rather than of this write, so it stays
# honest about what is being served while it is copied from session to
# session.
if [ -n "$freset$wreset" ]; then
  fh=null; sd=null
  [ -n "$freset" ] && fh=$(printf '{"used_percentage":%s,"resets_at":%s}' "$five" "$freset")
  [ -n "$wreset" ] && sd=$(printf '{"used_percentage":%s,"resets_at":%s}' "$week" "$wreset")
  tmp=$(mktemp "$HOME/.claude/.usage-cache.XXXXXX" 2>/dev/null) && {
    printf '{"five_hour":%s,"seven_day":%s,"seen_at":%s}\n' "$fh" "$sd" "$seen" > "$tmp" 2>/dev/null \
      && mv -f "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  }
fi

# BETWEEN 5h windows there is nothing to report: a payload drops five_hour
# once its window has passed, so the whole machine can be without one at the
# same time and the segment would vanish - taking the row's shape with it -
# for as long as the gap lasts, which is however long the machine is left
# alone. Between windows the usage IS 0, the next window not having started,
# so show the level; the new window's end is a server-side fact we do not have
# yet, so leave the reset time and the pace off until a payload reports them.
#
# seven_day gets no such treatment. Its window is a week long and is running
# essentially always, so an absent seven_day means "never heard", not "zero" -
# unless we watched the window expire, which is the one case where 0 is a fact.
# Persistence above is deliberately untouched: a level with no boundary is
# nothing to hand other sessions.
[ -z "$five" ] && five=0
[ -z "$week" ] && [ -n "$wrolled" ] && week=0

# pace_badge <pace> <used%> -> " <colored OK|WARN|CRIT>".
# Severity is the WORSE of two signals: the pace trajectory (burning faster
# than the window can sustain) and the absolute usage level (how close to the
# ceiling). So hitting ~100% always reads CRIT even when perfectly paced.
# OK=success, WARN=warning, CRIT=error - Claude Code's own semantic colours,
# reached through heat() at the ramp stops that carry them.
pace_badge() {
  local pace="$1" used="$2" ps=0 ls=0 sev lab hv
  [ -n "$pace" ] && ps=$(awk -v p="$pace" 'BEGIN{print (p>=1.5)?2:(p>=1.1)?1:0}')
  [ -n "$used" ] && ls=$(awk -v u="$used" 'BEGIN{print (u>=95)?2:(u>=85)?1:0}')
  # Nothing to show: no pace signal (too early) and usage not elevated.
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
if [ -n "$five" ]; then
  p=$(printf '%.0f' "$five")
  seg="5h $(heat "$p")${p}%${reset_c}"
  if [ -n "$freset" ]; then
    rt=$(date -d "@$freset" +%H:%M 2>/dev/null)
    [ -n "$rt" ] && seg="$seg →$rt"
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
fi

# 7-day window: usage% + reset date + pace badge.
# Budget is meant to last 5 working days (Mon-Fri); any 7-day window contains
# exactly 5 weekdays. Expected usage = elapsed working days / 5. Weekends do
# not add to the expected burn, so 1 working day used should sit near 20%.
if [ -n "$week" ]; then
  p=$(printf '%.0f' "$week")
  seg="7d $(heat "$p")${p}%${reset_c}"
  if [ -n "$wreset" ]; then
    rt=$(date -d "@$wreset" +'%-m/%-d' 2>/dev/null)
    [ -n "$rt" ] && seg="$seg →$rt"
  fi
  pace=""
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
