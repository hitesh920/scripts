#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/server-cleanup.sh
source "$SCRIPT_DIR/lib/server-cleanup.sh"

readonly RESET_CONFIRMATION="RESET DEVELOPMENT STATE"
readonly ALIASES_START="# >>> ubuntu-server-scripts aliases >>>"
readonly ALIASES_END="# <<< ubuntu-server-scripts aliases <<<"
readonly LOADER_START="# >>> ubuntu-server-scripts alias loader >>>"
readonly LOADER_END="# <<< ubuntu-server-scripts alias loader <<<"
readonly LEGACY_ALIASES_START="# >>> server-bootstrap aliases >>>"
readonly LEGACY_ALIASES_END="# <<< server-bootstrap aliases <<<"
readonly LEGACY_LOADER_START="# >>> server-bootstrap bash_aliases loader >>>"
readonly LEGACY_LOADER_END="# <<< server-bootstrap bash_aliases loader <<<"

DRY_RUN=false
FAILURES=0
TARGET_USER=
TARGET_UID=
TARGET_HOME=

trap 'echo "Error: server reset failed on line $LINENO." >&2' ERR

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run]

Reset Docker, Git/GitHub authentication, and suite-managed aliases while
preserving user files, projects, SSH, networking, firewall rules, users, and
cloud agents. Git, Python, pipx, and GitHub CLI remain installed.
EOF
}

resolve_target_user() {
  TARGET_USER=$(id -un)
  TARGET_UID=$(id -u)
  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

  [[ -n $TARGET_HOME && $TARGET_HOME == /home/* && $TARGET_HOME != /home/ ]] ||
    die "refusing unsafe home directory '${TARGET_HOME:-unknown}'"
  [[ -d $TARGET_HOME && ! -L $TARGET_HOME ]] ||
    die "target home must be an existing, non-symlinked directory"

  local resolved_home
  resolved_home=$(readlink -f -- "$TARGET_HOME")
  [[ $resolved_home == "$TARGET_HOME" ]] || die "target home does not resolve to itself: $TARGET_HOME"
}

print_reset_preview() {
  cat <<EOF
Full development reset
----------------------
Target user: $TARGET_USER
Target home: $TARGET_HOME
Mode: $([[ $DRY_RUN == true ]] && echo "dry run" || echo "live reset")

The reset removes:
  - Docker/containerd packages, services, data, repositories, and keys
  - rootless Docker/containerd state for $TARGET_USER
  - Git global configuration and stored HTTPS credentials
  - GitHub CLI authentication/configuration
  - aliases managed by this script suite
  - the disposable system data handled by clean-server.sh

The reset preserves:
  - every personal file and project under $TARGET_HOME, including .ssh
  - all project .git directories
  - Git, Python, pipx, and GitHub CLI packages
  - users, networking, firewall rules, SSH service, and cloud agents
EOF
}

stop_rootless_services() {
  local runtime_dir="/run/user/$TARGET_UID" service
  [[ -d $runtime_dir ]] || return 0
  log "Stopping rootless Docker services..."
  for service in docker.socket docker.service containerd.service; do
    if XDG_RUNTIME_DIR=$runtime_dir systemctl --user list-unit-files "$service" --no-legend 2>/dev/null |
      grep -q "^$service"; then
      run_optional env "XDG_RUNTIME_DIR=$runtime_dir" systemctl --user disable --now "$service"
    fi
  done
}

stop_system_services() {
  local service
  log "Stopping system Docker services..."
  for service in docker.socket docker.service containerd.service; do
    if systemctl list-unit-files "$service" --no-legend 2>/dev/null | grep -q "^$service"; then
      run_optional sudo systemctl disable --now "$service"
    fi
  done
}

remove_docker_snap() {
  if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
    log "Removing the Docker Snap package..."
    run_optional sudo snap remove --purge docker
  fi
}

purge_docker_packages() {
  local package
  local -a candidates=(
    docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin
    docker-compose-plugin docker-model-plugin docker.io docker-compose
    docker-compose-v2 docker-doc docker-engine docker-scan-plugin lxc-docker
    containerd.io containerd runc podman-docker moby-engine moby-cli moby-buildx
    moby-compose moby-containerd moby-runc
  )
  local -a installed=()
  for package in "${candidates[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
      installed+=("$package")
    fi
  done
  if ((${#installed[@]})); then
    log "Purging Docker and container runtime packages..."
    run_optional sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"
  else
    log "No known Docker packages are installed."
  fi
}

unmount_runtime_mounts() {
  local target
  local -a mounts=()
  while IFS= read -r target; do
    case $target in
      /run/docker|/run/docker/*|/run/containerd|/run/containerd/*|\
      /var/lib/docker|/var/lib/docker/*|/var/lib/containerd|/var/lib/containerd/*)
        mounts+=("$target")
        ;;
    esac
  done < <(findmnt -rn -o TARGET | sort -r)

  if ((${#mounts[@]})); then
    log "Unmounting leftover Docker runtime mounts..."
    for target in "${mounts[@]}"; do
      run_optional sudo umount --lazy -- "$target"
    done
  fi
}

remove_unowned_binary() {
  local path=$1
  [[ -e $path || -L $path ]] || return 0
  if dpkg-query -S "$path" >/dev/null 2>&1; then
    warn "preserving package-owned binary: $path"
  else
    run_optional sudo rm -f -- "$path"
  fi
}

remove_docker_system_state() {
  local binary
  log "Removing Docker data and system configuration..."
  run_optional sudo rm -rf -- \
    /var/lib/docker /var/lib/containerd /run/docker /run/containerd \
    /etc/docker /etc/containerd /etc/systemd/system/docker.service.d \
    /etc/systemd/system/containerd.service.d
  run_optional sudo rm -f -- \
    /run/docker.sock /etc/default/docker \
    /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources \
    /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg \
    /etc/apt/trusted.gpg.d/docker.gpg /usr/share/keyrings/docker.gpg \
    /usr/share/keyrings/docker-archive-keyring.gpg \
    /etc/systemd/system/docker.service /etc/systemd/system/docker.socket \
    /etc/systemd/system/containerd.service \
    /etc/systemd/system/multi-user.target.wants/docker.service \
    /etc/systemd/system/multi-user.target.wants/containerd.service \
    /etc/systemd/system/sockets.target.wants/docker.socket

  for binary in \
    /usr/local/bin/docker /usr/local/bin/dockerd /usr/local/bin/docker-compose \
    /usr/local/bin/containerd /usr/local/bin/ctr /usr/local/bin/runc \
    /usr/bin/docker /usr/bin/dockerd /usr/bin/docker-init /usr/bin/docker-proxy \
    /usr/bin/docker-compose /usr/bin/containerd /usr/bin/containerd-shim \
    /usr/bin/containerd-shim-runc-v1 /usr/bin/containerd-shim-runc-v2 \
    /usr/bin/ctr /usr/bin/runc \
    /usr/local/lib/docker/cli-plugins/docker-buildx \
    /usr/local/lib/docker/cli-plugins/docker-compose \
    /usr/local/libexec/docker/cli-plugins/docker-buildx \
    /usr/local/libexec/docker/cli-plugins/docker-compose \
    /usr/lib/docker/cli-plugins/docker-buildx \
    /usr/lib/docker/cli-plugins/docker-compose \
    /usr/libexec/docker/cli-plugins/docker-buildx \
    /usr/libexec/docker/cli-plugins/docker-compose; do
    remove_unowned_binary "$binary"
  done
  run_optional sudo systemctl daemon-reload
}

remove_user_development_state() {
  log "Removing Docker, Git, GitHub CLI, and managed alias configuration for $TARGET_USER..."
  run_optional rm -rf -- \
    "$TARGET_HOME/.docker" \
    "$TARGET_HOME/.local/share/docker" \
    "$TARGET_HOME/.local/share/containerd" \
    "$TARGET_HOME/.config/docker" \
    "$TARGET_HOME/.config/git" \
    "$TARGET_HOME/.config/gh"
  run_optional rm -f -- \
    "$TARGET_HOME/.gitconfig" \
    "$TARGET_HOME/.git-credentials" \
    "$TARGET_HOME/.config/systemd/user/docker.service" \
    "$TARGET_HOME/.config/systemd/user/docker.socket" \
    "$TARGET_HOME/.config/systemd/user/containerd.service" \
    "$TARGET_HOME/.config/systemd/user/default.target.wants/docker.service" \
    "$TARGET_HOME/.local/bin/docker" \
    "$TARGET_HOME/.local/bin/dockerd" \
    "$TARGET_HOME/.local/bin/dockerd-rootless.sh" \
    "$TARGET_HOME/.local/bin/dockerd-rootless-setuptool.sh"

  if [[ $DRY_RUN == true ]]; then
    print_command remove-managed-block "$TARGET_HOME/.bash_aliases" "$ALIASES_START" "$ALIASES_END"
    print_command remove-managed-block "$TARGET_HOME/.bashrc" "$LOADER_START" "$LOADER_END"
  else
    remove_managed_block "$TARGET_HOME/.bash_aliases" "$ALIASES_START" "$ALIASES_END"
    remove_managed_block "$TARGET_HOME/.bashrc" "$LOADER_START" "$LOADER_END"
    remove_managed_block "$TARGET_HOME/.bash_aliases" "$LEGACY_ALIASES_START" "$LEGACY_ALIASES_END"
    remove_managed_block "$TARGET_HOME/.bashrc" "$LEGACY_LOADER_START" "$LEGACY_LOADER_END"
  fi
}

remove_user_from_docker_group() {
  getent group docker >/dev/null 2>&1 || return 0
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    log "Removing $TARGET_USER from the docker group..."
    run_optional sudo gpasswd -d "$TARGET_USER" docker
  fi

  local gid members primary_users
  gid=$(getent group docker | cut -d: -f3)
  members=$(getent group docker | cut -d: -f4)
  primary_users=$(getent passwd | awk -F: -v gid="$gid" '$4 == gid { print $1 }')
  if [[ -z $members && -z $primary_users ]]; then
    run_optional sudo groupdel docker
  else
    warn "docker group still has members and was preserved"
  fi
}

offer_reboot() {
  local answer
  read -r -p "Reset succeeded. Type 'REBOOT' to reboot now, or press Enter to stay online: " answer
  if [[ $answer == REBOOT ]]; then
    sudo systemctl reboot
  else
    log "Reset complete. The server remains online."
  fi
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
  for command in sudo getent readlink findmnt sort systemctl umount apt-get dpkg-query awk; do
    require_command "$command"
  done
  resolve_target_user
  init_sudo
  print_reset_preview
  show_disk_summary

  if [[ $DRY_RUN != true ]]; then
    local confirmation
    read -r -p "Type '$RESET_CONFIRMATION' to continue: " confirmation
    if [[ $confirmation != "$RESET_CONFIRMATION" ]]; then
      log "Confirmation did not match. Nothing was changed."
      exit 0
    fi
  fi

  stop_rootless_services
  stop_system_services
  remove_docker_snap
  purge_docker_packages
  unmount_runtime_mounts
  remove_docker_system_state
  remove_user_from_docker_group
  remove_user_development_state
  perform_safe_cleanup
  finish_with_failures "Server reset"

  if [[ $DRY_RUN == true ]]; then
    log "Dry run complete. Nothing was changed and the server will not reboot."
  else
    offer_reboot
  fi
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
