#!/usr/bin/env bash
#
# Bootstrap a CLI development environment for WSL2 Ubuntu 24.04.
#
# This script is intended to be idempotent:
# - installed commands are skipped
# - apt update runs at most once
# - apt packages are installed in one batch where possible
#
# It installs common CLI tools, chezmoi, starship, Codex, and Claude Code.
# It does not manage credentials, API keys, or authentication state.
# It does not change the default shell automatically; see the final message.
#
# Safe to run on both personal and work machines, including systems where some
# tools are already installed.

set -euo pipefail

FAILED_COMMAND=""
trap 'FAILED_COMMAND=$BASH_COMMAND' DEBUG
trap 'printf "\n[ERROR] line %s: command failed: %s\n" "$LINENO" "$FAILED_COMMAND" >&2' ERR

installed=()
skipped=()
warned=()

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
  warned+=("$*")
}

mark_installed() {
  installed+=("$1")
  log "installed: $1"
}

mark_skipped() {
  skipped+=("$1")
  log "skipped: $1"
}

need_sudo() {
  if (( EUID == 0 )); then
    SUDO=()
  else
    if ! command -v sudo >/dev/null 2>&1; then
      printf '[ERROR] sudo is required but not installed.\n' >&2
      exit 1
    fi
    SUDO=(sudo)
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

download_installer() {
  local name="$1"
  local url="$2"
  local output="$3"

  if ! has_command curl; then
    printf '[ERROR] curl is required to install %s.\n' "$name" >&2
    exit 1
  fi

  log "downloading $name installer: $url"
  curl -fsSL "$url" -o "$output"
}

check_environment() {
  log "checking environment"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      warn "this script is intended for Ubuntu, but detected ID=${ID:-unknown}"
    fi
    if [[ "${VERSION_ID:-}" != "24.04" ]]; then
      warn "this script is intended for Ubuntu 24.04, but detected VERSION_ID=${VERSION_ID:-unknown}"
    fi
  else
    warn "/etc/os-release not found; cannot confirm Ubuntu version"
  fi

  if [[ ! -r /proc/sys/kernel/osrelease ]] || ! grep -qi 'microsoft.*WSL2\|WSL2' /proc/sys/kernel/osrelease; then
    warn "this script is intended for WSL2; WSL2 was not detected"
  fi
}

install_apt_packages() {
  local apt_packages=()

  if has_command git; then mark_skipped "git"; else apt_packages+=(git); fi
  if has_command zsh; then mark_skipped "zsh"; else apt_packages+=(zsh); fi
  if has_command tmux; then mark_skipped "tmux"; else apt_packages+=(tmux); fi
  if has_command rg; then mark_skipped "ripgrep"; else apt_packages+=(ripgrep); fi
  if ! has_command fd && ! has_command fdfind; then
    apt_packages+=(fd-find)
  else
    mark_skipped "fd-find"
  fi
  if has_command fzf; then mark_skipped "fzf"; else apt_packages+=(fzf); fi
  if has_command jq; then mark_skipped "jq"; else apt_packages+=(jq); fi
  if has_command nvim; then mark_skipped "neovim"; else apt_packages+=(neovim); fi
  if has_command curl; then mark_skipped "curl"; else apt_packages+=(curl); fi

  if [[ ! -r /etc/ssl/certs/ca-certificates.crt ]]; then
    apt_packages+=(ca-certificates)
  else
    mark_skipped "ca-certificates"
  fi

  if ((${#apt_packages[@]} == 0)); then
    mark_skipped "apt install"
    return
  fi

  need_sudo
  log "apt update will run once"
  "${SUDO[@]}" apt-get update
  log "installing apt packages: ${apt_packages[*]}"
  "${SUDO[@]}" apt-get install -y "${apt_packages[@]}"
  printf -v installed_packages '%s, ' "${apt_packages[@]}"
  mark_installed "apt packages: ${installed_packages%, }"
}

ensure_fd_command() {
  if has_command fd; then
    mark_skipped "fd symlink"
    return
  fi

  if ! has_command fdfind; then
    warn "fdfind is not available; cannot create fd symlink"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  if [[ -e "$HOME/.local/bin/fd" && ! -L "$HOME/.local/bin/fd" ]]; then
    warn "$HOME/.local/bin/fd exists and is not a symlink; leaving it unchanged"
    return
  fi

  ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  mark_installed "fd symlink: $HOME/.local/bin/fd"

  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "$HOME/.local/bin is not in PATH; fd may not be available until PATH is updated"
  fi
}

verify_base_tools() {
  log "verifying base commands"

  has_command git || warn "git command is still missing"
  has_command zsh || warn "zsh command is still missing"
  has_command tmux || warn "tmux command is still missing"
  has_command rg || warn "rg command is still missing"
  has_command fd || has_command fdfind || warn "fd/fdfind command is still missing"
  has_command fzf || warn "fzf command is still missing"
  has_command jq || warn "jq command is still missing"
  has_command nvim || warn "nvim command is still missing"
  has_command curl || warn "curl command is still missing"
}

install_starship() {
  if has_command starship; then
    mark_skipped "starship"
    return
  fi

  local installer="$TMP_DIR/starship-install.sh"
  download_installer "starship" "https://starship.rs/install.sh" "$installer"

  # External official installer notice:
  # Do not use "curl | sh" here. The installer is downloaded to a temporary
  # file first so it can be inspected/debugged if installation fails.
  need_sudo
  log "running starship official installer with sudo"
  "${SUDO[@]}" sh "$installer" -y -b /usr/local/bin
  mark_installed "starship"
}

install_chezmoi() {
  if has_command chezmoi; then
    mark_skipped "chezmoi"
    return
  fi

  local installer="$TMP_DIR/chezmoi-install.sh"
  download_installer "chezmoi" "https://get.chezmoi.io" "$installer"

  mkdir -p "$HOME/.local/bin"
  log "running chezmoi official installer"
  sh "$installer" -b "$HOME/.local/bin"
  hash -r

  if has_command chezmoi; then
    mark_installed "chezmoi"
  else
    warn "chezmoi installer finished, but chezmoi is not on PATH"
  fi
}

install_codex() {
  if has_command codex; then
    mark_skipped "codex"
    return
  fi

  local installer="$TMP_DIR/codex-install.sh"
  download_installer "codex" "https://chatgpt.com/codex/install.sh" "$installer"

  log "running codex official installer"
  sh "$installer"
  hash -r

  if has_command codex; then
    mark_installed "codex"
  else
    warn "codex installer finished, but codex is not on PATH"
  fi
}

install_claude_code() {
  if has_command claude; then
    mark_skipped "claude code"
    return
  fi

  local installer="$TMP_DIR/claude-install.sh"
  download_installer "claude code" "https://claude.ai/install.sh" "$installer"

  log "running claude code official installer"
  bash "$installer"
  hash -r

  if has_command claude; then
    mark_installed "claude code"
  else
    warn "claude code installer finished, but claude is not on PATH"
  fi
}

print_summary() {
  printf '\n========== install summary ==========\n'

  printf '\nInstalled:\n'
  if ((${#installed[@]} == 0)); then
    printf '  - none\n'
  else
    printf '  - %s\n' "${installed[@]}"
  fi

  printf '\nSkipped:\n'
  if ((${#skipped[@]} == 0)); then
    printf '  - none\n'
  else
    printf '  - %s\n' "${skipped[@]}"
  fi

  printf '\nWarnings:\n'
  if ((${#warned[@]} == 0)); then
    printf '  - none\n'
  else
    printf '  - %s\n' "${warned[@]}"
  fi

  cat <<'EOF'

Next commands:
  chezmoi apply
  chsh -s "$(which zsh)"

Note:
  The shell change command is intentionally not run automatically.
EOF
}

main() {
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  check_environment
  install_apt_packages
  ensure_fd_command
  verify_base_tools
  install_starship
  install_chezmoi
  install_codex
  install_claude_code
  print_summary
}

main "$@"
