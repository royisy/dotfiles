#!/usr/bin/env bash
# Mirror each Herdr tab's agent status into its tab label.
#
# Herdr already tracks per-tab agent state - `herdr tab list` returns
# agent_status for every tab - but only draws it in the sidebar agent list.
# This prefixes the same signal onto the tab label so the tab row carries it.
#
# The label is the only per-tab surface available: Herdr 0.8.2 exposes no
# colour anywhere in its API schema, and `tab rename` takes a label and
# nothing else. Renaming is safe to do repeatedly - it is not a focus command,
# so it does not mark a tab seen (verified: a `done` tab stays `done` across a
# rename, rather than collapsing back to `idle`).
#
# The indicator has to be an emoji, and is therefore two cells wide. Herdr
# draws tab labels as plain text, so an ANSI escape embedded in one is stored
# and drawn verbatim - the tab reads "^[[33m● memo" and gets wider rather than
# colourful (tried on a live tab) - and config cannot colour a tab either:
# [theme.custom] only redefines the global palette, with no per-tab or
# per-state hook. So the colour has to live in the character itself.
#
# idle is left unmarked. It is the resting state that most tabs sit in, so
# marking it is noise, and skipping it keeps those tabs at their natural width.
#
# Custom script; not managed by the Herdr integration installer.

set -uo pipefail

HERDR=${HERDR_BIN:-$HOME/.local/bin/herdr}
INTERVAL=${HERDR_TAB_STATUS_INTERVAL:-3}

usage() {
  cat <<'EOF'
Usage: tab-status.sh [--once] [--dry-run] [--strip]

  --once      Run a single pass instead of looping.
  --dry-run   Print the renames that would happen; change nothing.
  --strip     Remove all indicators and restore plain labels.
EOF
}

once=0; dry=0; strip_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1 ;;
    --dry-run) dry=1 ;;
    --strip) strip_only=1; once=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -x "$HERDR" ] || { echo "herdr not found at $HERDR" >&2; exit 1; }

# Emit "tab_id<TAB>desired_label" for tabs whose label is not already correct.
#
# Stripping the existing prefix before rebuilding it is what keeps this
# idempotent, and lets a tab renamed by hand (Herdr prefills the current label,
# indicator included) round-trip cleanly. Two of the glyphs are ZWJ sequences,
# so the strip pattern lists all three as whole alternatives - a character
# class can only ever consume one codepoint at a time.
# jq does the stripping because its regex engine is UTF-8 aware regardless of
# the caller's locale, which a sed character class of multi-byte glyphs is not.
plan() {
  "$HERDR" tab list 2>/dev/null | jq -r --argjson strip "$strip_only" '
    def glyph:
      if   . == "blocked" then "🙋"
      elif . == "working" then "👩‍💻"
      elif . == "done"    then "🙆‍♂️"
      else "" end;                     # idle, and any status Herdr adds later
    (.result.tabs // [])[]
    | (.label // "") as $cur
    | ($cur | sub("^(?:🙋|👩‍💻|🙆‍♂️|[[:space:]])+"; "")) as $base
    | (if $strip == 1 then "" else ((.agent_status // "") | glyph) end) as $g
    | select($base != "")
    | (if $g == "" then $base else $g + " " + $base end) as $want
    | select($want != $cur)
    | [.tab_id, $want] | @tsv
  '
}

pass() {
  local id want
  while IFS=$'\t' read -r id want; do
    [ -n "$id" ] || continue
    if [ "$dry" = 1 ]; then
      printf 'would rename %s -> %s\n' "$id" "$want"
    else
      "$HERDR" tab rename "$id" "$want" >/dev/null 2>&1 || true
    fi
  done < <(plan)
}

if [ "$once" = 1 ]; then
  pass
  exit 0
fi

# The server outliving this loop is normal (herdr update, server restart), and
# a failed pass is not worth exiting over: plan() yields nothing and the next
# tick retries.
while :; do
  pass
  sleep "$INTERVAL"
done
