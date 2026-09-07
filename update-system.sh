#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

trap 'echo "Error: system update failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Update and clean packages on a supported Ubuntu LTS server."
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
  init_sudo

  log "Updating package indexes..."
  sudo apt-get update
  log "Installing all available updates..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
  log "Removing unused packages..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
  log "Cleaning apt caches..."
  sudo apt-get autoclean
  sudo apt-get clean

  if [[ -f /var/run/reboot-required ]]; then
    log "Updates complete. A reboot is required."
    if [[ -r /var/run/reboot-required.pkgs ]]; then
      log "Packages requesting the reboot:"
      sed 's/^/  - /' /var/run/reboot-required.pkgs
    fi
  else
    log "Updates complete. No reboot is currently required."
  fi
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
