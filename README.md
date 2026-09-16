# dotfiles

Public dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Host types

During `chezmoi init`, choose one of:

- `workstation`: local development environment
- `vps`: remote Ubuntu research environment

The host type is stored in the machine-local chezmoi config. Hostnames,
project paths, credentials, authentication state, databases, and backups do
not belong in this repository.

Codex's `config.toml` is managed partially so machine-generated state and
trusted-project entries remain local. On VPS hosts, `h` launches Herdr
without requiring the full command name.

## Git identity

`user.name` and `user.email` are deliberately absent from `dot_gitconfig`:
this repository is public, and the identity differs per machine. After
`chezmoi apply`, create `~/.gitconfig.local`, which `~/.gitconfig` already
includes:

```ini
[user]
	name = Your Name
	email = you@example.com
```

Without it Git has no identity and `git commit` fails with
`Please tell me who you are`.

To use a second account for some repositories, add an `includeIf` *after* the
default `[user]` block so the later value wins, and pin the account name so the
credential helper picks the matching stored credential:

```ini
[credential "https://github.com"]
	username = default-account

[includeIf "gitdir:~/some-project/"]
	path = ~/.gitconfig.other
```

`gitdir:` also matches worktrees of that repository, since their Git directory
lives under `.git/worktrees/`. Prefer making the common account the default and
overriding the rarer one, rather than enumerating directories that are easy to
forget.

`~/.gitconfig.local` and the files it includes are machine-local and must never
be added to this repository.
