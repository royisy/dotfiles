#!/usr/bin/env bash
# Toggle a trailing 🛌 on the current Herdr tab's label, to mark a tab that
# needs no attention for a while. Run it again to take the mark off.
#
# The mark goes at the end because tab-status.sh owns the front of the label:
# it strips and rewrites only the leading status glyph, so a suffix survives
# its passes untouched ("👩‍💻 memo 🛌").
#
# Custom script; not managed by the Herdr integration installer.

set -uo pipefail

HERDR=${HERDR_BIN:-$HOME/.local/bin/herdr}
MARK='🛌'

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -x "$HERDR" ] || { echo "herdr not found at $HERDR" >&2; exit 1; }

# Resolve the tab from this shell's own pane. `pane current` is no substitute:
# outside Herdr it answers with whichever pane has focus, so a stray run would
# mark some other tab. HERDR_TAB_ID is set too, but it is fixed when the shell
# starts and goes stale if the pane is later moved to another tab.
[ -n "${HERDR_PANE_ID:-}" ] || { echo "not inside a Herdr pane" >&2; exit 1; }
tab=$("$HERDR" pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.tab_id // empty')
[ -n "$tab" ] || { echo "failed to find the tab of pane $HERDR_PANE_ID" >&2; exit 1; }

# Fail rather than read a failed lookup as an empty label, which would rename
# the tab to the bare mark.
label=$("$HERDR" tab get "$tab" 2>/dev/null |
  jq -er 'if .result.tab then (.result.tab.label // "") else null end') ||
  { echo "failed to read tab $tab" >&2; exit 1; }

case $label in
  *"$MARK")
    want=${label%"$MARK"}
    want=${want%"${want##*[![:space:]]}"}   # drop the separating space
    ;;
  *)
    want="${label:+$label }$MARK"
    ;;
esac

"$HERDR" tab rename "$tab" "$want" >/dev/null || { echo "failed to rename tab $tab" >&2; exit 1; }
printf '%s\n' "$want"
