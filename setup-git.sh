#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly DEFAULT_NAME="hitesh kamble"
readonly DEFAULT_EMAIL="hiteshkamble920@gmail.com"
readonly DEFAULT_USERNAME="hitesh920"
readonly GITHUB_HOST="github.com"

trap 'echo "Error: Git setup failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Configure Git identity and GitHub CLI authentication over HTTPS."
}

main() {
  case ${1:-} in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  verify_supported_ubuntu
  require_command git
  require_command gh

  local name email username
  read -r -p "Git name [$DEFAULT_NAME]: " name
  read -r -p "Git email [$DEFAULT_EMAIL]: " email
  read -r -p "GitHub username [$DEFAULT_USERNAME]: " username
  name=${name:-$DEFAULT_NAME}
  email=${email:-$DEFAULT_EMAIL}
  username=${username:-$DEFAULT_USERNAME}

  git config --global user.name "$name"
  git config --global user.email "$email"
  git config --global credential.https://github.com.username "$username"

  if gh auth status --hostname "$GITHUB_HOST" >/dev/null 2>&1; then
    log "GitHub CLI is already authenticated."
    if confirm_yes "Reauthenticate the GitHub CLI account?"; then
      gh auth logout --hostname "$GITHUB_HOST"
      gh auth login --hostname "$GITHUB_HOST" --git-protocol https --web
    fi
  else
    log "Starting GitHub CLI browser/device authentication..."
    gh auth login --hostname "$GITHUB_HOST" --git-protocol https --web
  fi

  gh auth setup-git --hostname "$GITHUB_HOST"
  gh auth status --hostname "$GITHUB_HOST"
  log "Git identity and GitHub HTTPS authentication are configured."
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
