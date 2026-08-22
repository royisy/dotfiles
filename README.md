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
