#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/server-cleanup.sh
source "$SCRIPT_DIR/lib/server-cleanup.sh"

DRY_RUN=false
FAILURES=0

trap 'echo "Error: safe server cleanup failed on line $LINENO." >&2' ERR

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run]

Clean disposable Ubuntu system data while preserving user files,
configuration, projects, SSH, networking, cloud agents, and Docker data.
EOF
}

main() {
  case ${1:-} in
    "") ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  verify_supported_ubuntu
  for command in apt-get awk df du find journalctl systemd-tmpfiles; do
    require_command "$command"
  done
  init_sudo

  cat <<'EOF'
Safe server cleanup
-------------------
Removes unused apt packages, apt caches, disabled Snap revisions, crash dumps,
systemd-managed temporary files, and journal entries older than 14 days.

Preserves user files and configuration, projects, SSH, networking, firewall
rules, cloud agents, installed applications, and all Docker data.
EOF
  show_disk_summary

  if [[ $DRY_RUN != true ]] && ! confirm_yes "Proceed with safe cleanup?"; then
    log "Cleanup cancelled. Nothing was changed."
    exit 0
  fi

  perform_safe_cleanup
  finish_with_failures "Safe cleanup"

  if [[ $DRY_RUN == true ]]; then
    log "Dry run complete. Nothing was changed."
  else
    log "Safe cleanup complete."
    show_disk_summary
  fi
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
