#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

trap 'echo "Error: development tool installation failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Install Git, Ubuntu Python tooling, pipx, and GitHub CLI."
}

install_github_cli_repository() {
  local key_temp
  key_temp=$(mktemp)
  trap 'rm -f -- "$key_temp"' RETURN

  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$key_temp"
  sudo install -m 0755 -d /etc/apt/keyrings /etc/apt/sources.list.d
  sudo install -m 0644 "$key_temp" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  rm -f -- "$key_temp"
  trap - RETURN
}

main() {
  case ${1:-} in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  verify_supported_ubuntu
  require_command apt-get
  require_command dpkg
  init_sudo

  log "Installing base development tools..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl gnupg git python3 python3-pip python3-venv pipx
  require_command curl

  log "Configuring GitHub CLI's official apt repository..."
  install_github_cli_repository
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y gh

  python3 -m pipx ensurepath

  log "Installed versions:"
  git --version
  python3 --version
  python3 -m pip --version
  pipx --version
  gh --version | head -n 1
  log "Development tools are ready. Start a new shell if pipx changed PATH."
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
