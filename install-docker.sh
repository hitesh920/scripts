#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

trap 'echo "Error: Docker installation failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Install the latest stable Docker Engine from Docker's official repository."
}

main() {
  case ${1:-} in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  verify_supported_ubuntu
  for command in sudo apt-get dpkg dpkg-query getent systemctl; do
    require_command "$command"
  done
  init_sudo

  local current_user architecture ubuntu_codename key_temp package
  local -a conflicts=(
    docker.io docker-compose docker-compose-v2 docker-doc docker-buildx
    podman-docker containerd runc
  )
  local -a installed_conflicts=()
  current_user=$(id -un)
  # shellcheck source=/dev/null
  source /etc/os-release
  ubuntu_codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
  [[ -n $ubuntu_codename ]] || die "could not determine the Ubuntu codename"

  for package in "${conflicts[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii'; then
      installed_conflicts+=("$package")
    fi
  done
  if ((${#installed_conflicts[@]})); then
    log "Removing packages that conflict with Docker Engine..."
    sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${installed_conflicts[@]}"
  fi

  log "Configuring Docker's official apt repository..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  require_command curl
  key_temp=$(mktemp)
  trap 'rm -f -- "$key_temp"' RETURN
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$key_temp"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo install -m 0644 "$key_temp" /etc/apt/keyrings/docker.asc
  rm -f -- "$key_temp"
  trap - RETURN

  architecture=$(dpkg --print-architecture)
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  log "Installing Docker Engine, Buildx, and Compose..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker

  if ! getent group docker >/dev/null 2>&1; then
    sudo groupadd docker
  fi
  sudo usermod -aG docker "$current_user"

  log "Verifying Docker installation..."
  sudo docker version --format 'Docker Engine: {{.Server.Version}}'
  sudo docker compose version
  log "Docker installation complete. Log out and back in before using Docker without sudo."
  warn "membership in the docker group grants root-equivalent privileges"
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
