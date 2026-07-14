#!/usr/bin/env bash
#
# Bootstrap a CLI development environment for WSL2 Ubuntu 24.04.
#
# This script is intended to be idempotent:
# - installed commands are skipped
# - apt update runs at most once
# - apt packages are installed in one batch where possible
#
# It installs common CLI tools, Herdr, chezmoi, Oh My Zsh, Codex, and Claude Code.
# It does not manage credentials, API keys, or authentication state.
# It does not change the default shell automatically; see the final message.
#
# Safe to run on both personal and work machines, including systems where some
# tools are already installed.

set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-0.12.4}"

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

# Whether apt-get can run with sudo without blocking on an unanswerable prompt.
# True when: running as root, sudo credentials are already cached/passwordless,
# or a terminal is attached so sudo can prompt interactively. False only when
# sudo would need a password but there is no tty to enter it (e.g. non-interactive
# runs); callers should skip apt gracefully instead of hard-failing.
apt_sudo_ready() {
  (( EUID == 0 )) && return 0
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true 2>/dev/null && return 0
  [ -t 0 ] && return 0
  return 1
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
  if [[ "${SKIP_APT:-0}" == "1" ]]; then
    mark_skipped "apt install"
    return
  fi

  local apt_packages=()

  # Note: bat, delta, ripgrep, eza, and zoxide are installed from GitHub releases into
  # ~/.local/bin (see install_user_local_cli_tools), so they are intentionally not
  # listed here. apt only handles tools that have no user-local installer.
  if has_command git; then mark_skipped "git"; else apt_packages+=(git); fi
  if has_command zsh; then mark_skipped "zsh"; else apt_packages+=(zsh); fi
  if ! has_command fd && ! has_command fdfind; then
    apt_packages+=(fd-find)
  else
    mark_skipped "fd-find"
  fi
  if has_command fzf; then mark_skipped "fzf"; else apt_packages+=(fzf); fi
  if has_command jq; then mark_skipped "jq"; else apt_packages+=(jq); fi
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

  if ! apt_sudo_ready; then
    warn "apt skipped: sudo unavailable non-interactively (set SKIP_APT=1 to silence). Missing: ${apt_packages[*]}"
    mark_skipped "apt install (no sudo)"
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

ensure_bat_command() {
  if has_command bat; then
    mark_skipped "bat symlink"
    return
  fi

  if ! has_command batcat; then
    warn "batcat is not available; cannot create bat symlink"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  if [[ -e "$HOME/.local/bin/bat" && ! -L "$HOME/.local/bin/bat" ]]; then
    warn "$HOME/.local/bin/bat exists and is not a symlink; leaving it unchanged"
    return
  fi

  ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
  mark_installed "bat symlink: $HOME/.local/bin/bat"

  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    warn "$HOME/.local/bin is not in PATH; bat may not be available until PATH is updated"
  fi
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
  has_command herdr || warn "herdr command is still missing"
  has_command bat || has_command batcat || warn "bat/batcat command is still missing"
  has_command delta || warn "delta command is still missing"
  has_command rg || warn "rg command is still missing"
  has_command fd || has_command fdfind || warn "fd/fdfind command is still missing"
  has_command fzf || warn "fzf command is still missing"
  has_command zoxide || warn "zoxide command is still missing"
  has_command jq || warn "jq command is still missing"
  has_command nvim || warn "nvim command is still missing"
  has_command curl || warn "curl command is still missing"
}

github_linux_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv6l) printf 'armv6' ;;
    *)
      warn "unsupported architecture: $(uname -m)"
      return 1
      ;;
  esac
}

github_latest_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r '.tag_name'
}

install_release_binary() {
  local name="$1"
  local url="$2"
  local archive="$3"
  local binary_path="$4"

  if ! has_command curl || ! has_command tar; then
    printf '[ERROR] curl and tar are required to install %s.\n' "$name" >&2
    exit 1
  fi

  download_installer "$name" "$url" "$TMP_DIR/$archive"
  mkdir -p "$TMP_DIR/$name" "$HOME/.local/bin"
  tar -xzf "$TMP_DIR/$archive" -C "$TMP_DIR/$name"
  install -m 0755 "$TMP_DIR/$name/$binary_path" "$HOME/.local/bin/$name"
  mark_installed "$name"
}

install_neovim() {
  local arch archive extracted_dir install_dir installed_version
  arch="$(github_linux_arch)"
  archive="nvim-linux-${arch}.tar.gz"
  extracted_dir="$TMP_DIR/nvim-linux-${arch}"
  install_dir="$HOME/.local/opt/nvim-linux-${arch}"
  installed_version=""

  if has_command nvim; then
    installed_version="$(nvim --version | head -n 1)"
  fi
  if [[ "$installed_version" == "NVIM v${NVIM_VERSION}" ]]; then
    mark_skipped "neovim ${NVIM_VERSION}"
    return
  fi

  if ! has_command curl || ! has_command tar; then
    printf '[ERROR] curl and tar are required to install Neovim.\n' >&2
    exit 1
  fi

  download_installer "neovim ${NVIM_VERSION}" \
    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/${archive}" \
    "$TMP_DIR/$archive"
  tar -xzf "$TMP_DIR/$archive" -C "$TMP_DIR"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  rm -rf "$install_dir"
  mv "$extracted_dir" "$install_dir"
  ln -sfn "$install_dir/bin/nvim" "$HOME/.local/bin/nvim"
  mark_installed "neovim ${NVIM_VERSION}"
}

install_bat() {
  if has_command bat; then
    mark_skipped "bat"
    return
  fi

  if has_command batcat; then
    mark_skipped "bat release"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install bat from GitHub releases.\n' >&2
    exit 1
  fi

  local tag version archive
  tag="$(github_latest_tag sharkdp/bat)"
  version="${tag#v}"
  archive="bat-v${version}-x86_64-unknown-linux-gnu.tar.gz"
  install_release_binary "bat" "https://github.com/sharkdp/bat/releases/download/${tag}/${archive}" "$archive" "bat-v${version}-x86_64-unknown-linux-gnu/bat"
}

install_delta() {
  if has_command delta; then
    mark_skipped "delta"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install delta from GitHub releases.\n' >&2
    exit 1
  fi

  local tag archive
  tag="$(github_latest_tag dandavison/delta)"
  archive="delta-${tag}-x86_64-unknown-linux-gnu.tar.gz"
  install_release_binary "delta" "https://github.com/dandavison/delta/releases/download/${tag}/${archive}" "$archive" "delta-${tag}-x86_64-unknown-linux-gnu/delta"
}

install_ripgrep() {
  if has_command rg; then
    mark_skipped "ripgrep"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install ripgrep from GitHub releases.\n' >&2
    exit 1
  fi

  local tag archive
  tag="$(github_latest_tag BurntSushi/ripgrep)"
  archive="ripgrep-${tag}-x86_64-unknown-linux-musl.tar.gz"
  install_release_binary "rg" "https://github.com/BurntSushi/ripgrep/releases/download/${tag}/${archive}" "$archive" "ripgrep-${tag}-x86_64-unknown-linux-musl/rg"
}

install_eza() {
  if has_command eza; then
    mark_skipped "eza"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install eza from GitHub releases.\n' >&2
    exit 1
  fi

  local tag archive
  tag="$(github_latest_tag eza-community/eza)"
  archive="eza_x86_64-unknown-linux-musl.tar.gz"
  install_release_binary "eza" "https://github.com/eza-community/eza/releases/download/${tag}/${archive}" "$archive" "eza"
}

install_zoxide() {
  if has_command zoxide; then
    mark_skipped "zoxide"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install zoxide from GitHub releases.\n' >&2
    exit 1
  fi

  local tag version archive
  tag="$(github_latest_tag ajeetdsouza/zoxide)"
  version="${tag#v}"
  archive="zoxide-${version}-x86_64-unknown-linux-musl.tar.gz"
  install_release_binary "zoxide" "https://github.com/ajeetdsouza/zoxide/releases/download/${tag}/${archive}" "$archive" "zoxide"
}

install_lazygit() {
  if has_command lazygit; then
    mark_skipped "lazygit"
    return
  fi

  if ! has_command curl || ! has_command jq || ! has_command tar; then
    printf '[ERROR] curl, jq, and tar are required to install lazygit.\n' >&2
    exit 1
  fi

  local lazygit_arch
  lazygit_arch="$(github_linux_arch)" || return

  local tag version archive url checksums
  tag="$(github_latest_tag jesseduffield/lazygit)"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    printf '[ERROR] could not determine latest lazygit release.\n' >&2
    exit 1
  fi

  version="${tag#v}"
  archive="lazygit_${version}_linux_${lazygit_arch}.tar.gz"
  url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/${archive}"
  checksums="$TMP_DIR/lazygit-checksums.txt"

  download_installer "lazygit" "$url" "$TMP_DIR/$archive"
  download_installer "lazygit checksums" "https://github.com/jesseduffield/lazygit/releases/download/${tag}/checksums.txt" "$checksums"
  grep "  $archive\$" "$checksums" | (cd "$TMP_DIR" && sha256sum -c -)

  tar -xzf "$TMP_DIR/$archive" -C "$TMP_DIR" lazygit
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$TMP_DIR/lazygit" "$HOME/.local/bin/lazygit"
  mark_installed "lazygit $tag"
}

install_hunk() {
  if has_command hunk; then
    mark_skipped "hunk"
    return
  fi

  if ! has_command jq; then
    printf '[ERROR] jq is required to install hunk from GitHub releases.\n' >&2
    exit 1
  fi

  # hunk release assets use x64/arm64 rather than the x86_64/arm64 naming used elsewhere.
  local hunk_arch
  case "$(uname -m)" in
    x86_64|amd64) hunk_arch="x64" ;;
    aarch64|arm64) hunk_arch="arm64" ;;
    *)
      warn "unsupported architecture for hunk: $(uname -m)"
      return
      ;;
  esac

  local tag archive
  tag="$(github_latest_tag modem-dev/hunk)"
  archive="hunkdiff-linux-${hunk_arch}.tar.gz"
  install_release_binary "hunk" "https://github.com/modem-dev/hunk/releases/download/${tag}/${archive}" "$archive" "hunkdiff-linux-${hunk_arch}/hunk"
}

install_user_local_cli_tools() {
  install_bat
  install_delta
  install_ripgrep
  install_eza
  install_zoxide
  install_lazygit
  install_hunk
}

install_nvim_plugin() {
  local name="$1"
  local repo="$2"
  local plugin_dir="$HOME/.local/share/nvim/site/pack/plugins/start/$name"

  if [[ -d "$plugin_dir" ]]; then
    mark_skipped "nvim plugin: $name"
    return
  fi

  if ! has_command git; then
    printf '[ERROR] git is required to install Neovim plugin: %s.\n' "$name" >&2
    exit 1
  fi

  log "cloning Neovim plugin: $name"
  git clone --depth=1 "$repo" "$plugin_dir"
  mark_installed "nvim plugin: $name"
}

install_nvim_plugins() {
  install_nvim_plugin "fzf-lua" "https://github.com/ibhagwan/fzf-lua.git"
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    mark_skipped "oh-my-zsh"
    return
  fi

  if ! has_command git; then
    printf '[ERROR] git is required to install Oh My Zsh.\n' >&2
    exit 1
  fi

  log "cloning Oh My Zsh"
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  mark_installed "oh-my-zsh"
}

install_oh_my_zsh_plugin() {
  local name="$1"
  local repo="$2"
  local plugin_dir="$HOME/.oh-my-zsh/custom/plugins/$name"

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh is not installed; cannot install plugin: $name"
    return
  fi

  if [[ -d "$plugin_dir" ]]; then
    mark_skipped "oh-my-zsh plugin: $name"
    return
  fi

  if ! has_command git; then
    printf '[ERROR] git is required to install Oh My Zsh plugin: %s.\n' "$name" >&2
    exit 1
  fi

  log "cloning Oh My Zsh plugin: $name"
  git clone --depth=1 "$repo" "$plugin_dir"
  mark_installed "oh-my-zsh plugin: $name"
}

install_oh_my_zsh_plugins() {
  install_oh_my_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
  install_oh_my_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
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

install_herdr() {
  if has_command herdr; then
    mark_skipped "herdr"
    return
  fi

  local installer="$TMP_DIR/herdr-install.sh"
  download_installer "herdr" "https://herdr.dev/install.sh" "$installer"

  log "running herdr official installer"
  sh "$installer"
  hash -r

  if has_command herdr; then
    mark_installed "herdr"
  else
    warn "herdr installer finished, but herdr is not on PATH"
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
  install_neovim
  install_user_local_cli_tools
  ensure_bat_command
  ensure_fd_command
  install_herdr
  verify_base_tools
  install_nvim_plugins
  install_oh_my_zsh
  install_oh_my_zsh_plugins
  install_chezmoi
  install_codex
  install_claude_code
  print_summary
}

main "$@"
