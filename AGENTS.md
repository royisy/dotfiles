# Codex Instructions

- Before running `git commit`, show the staged diff, proposed commit message, author, and exact commit command, then ask for explicit user approval.
- Before running `git push` or any history-rewriting Git command, show the exact command and ask for explicit user approval.
- Do not create, amend, or push commits unless the user has approved that specific Git operation in the current conversation.

## Never commit machine-specific paths

This repository is public. Absolute paths that carry the user's home directory or account name (`/home/<user>/...`, `/Users/<user>/...`, `C:\Users\<user>\...`) must never enter a commit.

- Write `$HOME` or `~` instead. In JSON, `"sh \"$HOME/.claude/hooks/foo.sh\""` expands; `'$HOME/...'` inside single quotes does not.
- Some tools write absolute paths into managed files on their own (the Herdr integration does this to `~/.claude/settings.json`). Re-check such files whenever they are re-added with `chezmoi add`, not just when editing them by hand.
- When a managed file genuinely needs an absolute path, make it a chezmoi template (`*.tmpl`) and write `{{ .chezmoi.homeDir }}`. Build the template by hand: `chezmoi add --autotemplate` over-substitutes badly here, replacing every `:` and `/` in the file and resolving the home path to the unstable `{{ .chezmoi.commandDir }}`.
- Before committing, grep the staged diff and fix every hit:

  ```sh
  git diff --cached | grep -nE '/home/|/Users/|C:\\Users' && echo 'machine-specific path in staged diff'
  ```

## Config the app writes: never `chezmoi add` it

`~/.claude/settings.json` and `~/.codex/config.toml` are written by the tools
themselves — plugin installs, `/config`, `/model`, NUX counters — so this repo
cannot own them whole. Both are managed as chezmoi `modify_` scripts that
receive the live file, assert only the keys this repo owns, and pass everything
else through. Claude Code's own docs spell out the failure mode for a file
another tool generates: the change "applies to the current session and is gone
in the next one".

- Edit the `modify_` script. `chezmoi add` on either path replaces it with a
  snapshot of the live file, which loses the merge and can drag work-specific
  entries (plugins, MCP servers) into this public repo.
- `chezmoi apply` with no arguments touches every managed file, so check
  `chezmoi status` first — the two files above drift by design, and a file not
  yet converted to `modify_` would be overwritten.
