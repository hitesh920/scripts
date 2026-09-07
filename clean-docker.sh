#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly FORCE_CONFIRMATION="DELETE ALL DOCKER DATA"
DRY_RUN=false
FAILURES=0

trap 'echo "Error: Docker cleanup failed on line $LINENO." >&2' ERR

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run]

Interactively prune unused Docker data or force-delete all standalone Docker
resources on the current daemon. Swarm objects, plugins, and other contexts are
never targeted.
EOF
}

normal_cleanup() {
  local network attachments
  local -a networks=()

  log "Removing stopped containers..."
  run_optional docker container prune --force
  log "Removing images not used by a container..."
  run_optional docker image prune --all --force
  log "Removing unused volumes..."
  run_optional docker volume prune --all --force
  log "Removing unused local custom networks..."
  mapfile -t networks < <(docker network ls --quiet --filter type=custom --filter scope=local)
  for network in "${networks[@]}"; do
    attachments=$(docker network inspect --format '{{len .Containers}}' "$network" 2>/dev/null || true)
    if [[ $attachments == 0 ]]; then
      run_optional docker network rm "$network"
    fi
  done
  log "Removing unused build cache..."
  run_optional docker builder prune --all --force
}

force_remove_ids() {
  local resource=$1 force_flag=$2
  shift 2
  local -a ids=("$@")
  ((${#ids[@]})) || return 0
  if [[ -n $force_flag ]]; then
    run_optional docker "$resource" rm "$force_flag" "${ids[@]}"
  else
    run_optional docker "$resource" rm "${ids[@]}"
  fi
}

force_cleanup() {
  local -a containers=() images=() volumes=() networks=()
  mapfile -t containers < <(docker container ls --all --quiet)
  mapfile -t images < <(docker image ls --all --quiet | sort -u)
  mapfile -t volumes < <(docker volume ls --quiet)
  mapfile -t networks < <(docker network ls --quiet --filter type=custom --filter scope=local)

  log "Removing all containers, including running containers..."
  force_remove_ids container --force "${containers[@]}"
  log "Removing all images..."
  force_remove_ids image --force "${images[@]}"
  log "Removing all volumes..."
  force_remove_ids volume --force "${volumes[@]}"
  log "Removing all local custom networks..."
  force_remove_ids network "" "${networks[@]}"
  log "Removing all build cache and any unused leftovers..."
  run_optional docker builder prune --all --force
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
  require_command docker
  require_command sort
  docker info >/dev/null 2>&1 || die "cannot access the Docker daemon; log out and back in after joining the docker group"

  log "Docker context: $(docker context show)"
  cat <<'EOF'
1) Normal cleanup - remove only unused standalone resources
2) Force cleanup  - remove all standalone resources, including running containers
3) Cancel
EOF

  local choice confirmation
  read -r -p "Choose [1-3]: " choice
  case $choice in
    1)
      if [[ $DRY_RUN != true ]] && ! confirm_yes "Run normal Docker cleanup?"; then
        log "Cleanup cancelled. Nothing was changed."
        exit 0
      fi
      normal_cleanup
      ;;
    2)
      cat <<'EOF'
WARNING: force cleanup permanently removes every standalone container, image,
volume, local custom network, and build cache on the current Docker daemon.
Running containers and Compose applications will be destroyed.
EOF
      if [[ $DRY_RUN != true ]]; then
        read -r -p "Type '$FORCE_CONFIRMATION' to continue: " confirmation
        if [[ $confirmation != "$FORCE_CONFIRMATION" ]]; then
          log "Confirmation did not match. Nothing was changed."
          exit 0
        fi
      fi
      force_cleanup
      ;;
    3)
      log "Cleanup cancelled. Nothing was changed."
      exit 0
      ;;
    *)
      die "invalid choice; nothing was changed"
      ;;
  esac

  finish_with_failures "Docker cleanup"
  if [[ $DRY_RUN == true ]]; then
    log "Dry run complete. Nothing was changed."
  else
    log "Docker cleanup complete."
  fi
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
