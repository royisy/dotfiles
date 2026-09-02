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
# Custom script; not managed by the Herdr integration installer.

set -uo pipefail

HERDR=${HERDR_BIN:-$HOME/.local/bin/herdr}
INTERVAL=${HERDR_TAB_STATUS_INTERVAL:-3}
# Indicator styles:
#   faces   - people emoji: hand up / at the keyboard / OK gesture. Two of
#             these are ZWJ sequences, so the strip pattern matches them as
#             whole alternatives rather than through the character class,
#             which can only ever consume one codepoint at a time. The
#             runner the working glyph used to be stays in that pattern, so
#             a label still carrying one strips cleanly.
#   marks   - emoji whose SHAPE carries the meaning (stop / hourglass / check),
#             so the state reads without decoding a colour.
#   color   - colour-coded circles; meaning carried by hue alone.
#   compact - single-cell ASCII marks, no separator. Narrowest, monochrome.
#   symbols - wider monochrome glyphs.
#
# The emoji styles leave idle unmarked. It is the resting state that most tabs
# sit in, so marking it is noise, and skipping it keeps those tabs at their
# natural width.
#
# Colouring the label text is NOT possible, and neither is a smaller coloured
# mark. Herdr draws tab labels as plain text: an ANSI escape embedded in a
# label is stored and drawn verbatim, so the tab reads "^[[33m●^[[0m memo" and
# gets wider rather than colourful (tried on a live tab). Config cannot colour
# a tab either - Herdr 0.8.2 exposes no colour field anywhere in its API, and
# [theme.custom] only redefines the global palette, with no per-tab or
# per-state hook. So the colour has to live in the character, which means
# emoji presentation, which is always two cells wide. Colour and narrowness
# cannot both be had; compact trades the colour away for one cell.
STYLE=${HERDR_TAB_STATUS_STYLE:-faces}

usage() {
  cat <<'EOF'
Usage: tab-status.sh [--once] [--dry-run] [--style faces|marks|color|compact|symbols] [--tab ID]

  --once            Run a single pass instead of looping.
  --dry-run         Print the renames that would happen; change nothing.
  --style STYLE     Indicator style (default: faces, or $HERDR_TAB_STATUS_STYLE).
  --tab ID          Restrict the pass to one tab, for trying a style out.
  --strip           Remove all indicators and restore plain labels.
EOF
}

once=0; dry=0; only_tab=""; strip_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1 ;;
    --dry-run) dry=1 ;;
    --strip) strip_only=1; once=1 ;;
    --style) shift; STYLE=${1:-}; [ -n "$STYLE" ] || { usage >&2; exit 2; } ;;
    --tab) shift; only_tab=${1:-}; [ -n "$only_tab" ] || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$STYLE" in faces|marks|color|compact|symbols) ;; *) echo "unknown style: $STYLE" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -x "$HERDR" ] || { echo "herdr not found at $HERDR" >&2; exit 1; }

# Emit "tab_id<TAB>desired_label" for tabs whose label is not already correct.
#
# Stripping the existing prefix before rebuilding it is what keeps this
# idempotent, lets styles be switched without leaving debris, and lets a tab
# renamed by hand (Herdr prefills the current label, indicators included)
# round-trip cleanly. The strip pattern must cover every glyph of every style
# plus ANSI escapes, or switching styles would stack prefixes.
# jq does the stripping because its regex engine is UTF-8 aware regardless of
# the caller's locale, which a sed character class of multi-byte glyphs is not.
plan() {
  "$HERDR" tab list 2>/dev/null | jq -r \
    --arg style "$STYLE" --arg only "$only_tab" --argjson strip "$strip_only" '
    def glyph:
      if $style == "faces" then
        if   . == "blocked" then "\ud83d\ude4b"
        elif . == "working" then "👩‍💻"
        elif . == "done"    then "🙆‍♂️"
        else "" end                      # idle: unmarked, it is the resting state
      elif $style == "marks" then
        if   . == "blocked" then "\u2757"
        elif . == "working" then "\u23f3"
        elif . == "done"    then "\u2705"
        else "" end                      # idle: unmarked, it is the resting state
      elif $style == "color" then
        if   . == "blocked" then "\ud83d\udd34"
        elif . == "working" then "\ud83d\udfe1"
        elif . == "done"    then "\ud83d\udfe2"
        else "" end                      # idle: unmarked, it is the resting state
      elif $style == "compact" then
        if   . == "blocked" then "!"
        elif . == "working" then "*"
        elif . == "done"    then "+"
        elif . == "idle"    then "."
        else "" end
      else
        if   . == "blocked" then "●"
        elif . == "working" then "⏳"
        elif . == "done"    then "✓"
        elif . == "idle"    then "・"
        else "" end
      end;
    def sep: if $style == "compact" then "" else " " end;
    (.result.tabs // [])[]
    | select($only == "" or .tab_id == $only)
    | (.label // "") as $cur
    | ($cur | sub("^(?:\\[[0-9;]*m|👩‍💻|🏃‍♀️‍➡️|🏃‍♂️‍➡️|🙆‍♂️|[●⏳✓・!*+.\ud83d\udd34\ud83d\udfe1\ud83d\udfe2\u26aa\u2757\u2705\ud83d\ude21\ud83d\ude30\ud83d\ude0e\ud83d\ude4b]|[[:space:]])+"; "")) as $base
    | (if $strip == 1 then "" else ((.agent_status // "") | glyph) end) as $g
    | select($base != "")
    | (if $g == "" then $base else $g + sep + $base end) as $want
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
