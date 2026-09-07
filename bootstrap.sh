#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

trap 'echo "Error: bootstrap failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Update Ubuntu and install Git, Python, GitHub CLI, and Docker."
}

offer_script() {
  local description=$1 script=$2
  if confirm_yes "$description"; then
    "$SCRIPT_DIR/$script"
  else
    log "Skipped $script."
  fi
}

main() {
  case ${1:-} in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  verify_supported_ubuntu

  "$SCRIPT_DIR/update-system.sh"
  "$SCRIPT_DIR/install-dev-tools.sh"
  "$SCRIPT_DIR/install-docker.sh"

  echo
  offer_script "Configure Git identity and GitHub authentication now?" setup-git.sh
  offer_script "Install the managed Bash aliases now?" setup-aliases.sh

  echo
  log "Bootstrap complete."
  log "Log out and back in before using Docker without sudo."
  if [[ -f /var/run/reboot-required ]]; then
    log "Ubuntu reports that a reboot is required."
  fi
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
