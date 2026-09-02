#!/bin/sh
# Sync the Claude session name (set with /rename) to the Herdr pane label.
#
# Claude Code draws the session name in the prompt bar only, so it disappears
# whenever a selection or permission dialog replaces the input box. The Herdr
# pane label is drawn by Herdr itself and stays visible through those dialogs.
#
# Custom hook; not managed by the Herdr integration installer.

set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

hook_input=$(cat 2>/dev/null) || exit 0
session_id=$(printf '%s' "$hook_input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$session_id" ] || exit 0

# Subagents share the pane with their parent; only the main session owns the label.
agent_id=$(printf '%s' "$hook_input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
[ -z "$agent_id" ] || exit 0

# Claude records /rename in its session registry as name + nameSource "user".
# Auto-generated topic titles carry a different nameSource and are ignored, so a
# pane keeps whatever label it already has until its session is named by hand.
registry=""
for candidate in $(grep -ls "\"sessionId\":\"$session_id\"" "$HOME"/.claude/sessions/*.json 2>/dev/null || true); do
  if [ -z "$registry" ] || [ "$candidate" -nt "$registry" ]; then
    registry="$candidate"
  fi
done
[ -n "$registry" ] || exit 0

name=$(jq -r 'select(.nameSource == "user") | .name // empty' "$registry" 2>/dev/null || true)
[ -n "$name" ] || exit 0

# Only write when the label would actually change; a pane read costs ~3ms.
current=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '.result.pane.label // empty' 2>/dev/null || true)
[ "$current" != "$name" ] || exit 0

herdr pane rename "$HERDR_PANE_ID" "$name" >/dev/null 2>&1 || exit 0
