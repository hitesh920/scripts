#!/usr/bin/env bash

# Shared helpers for the Ubuntu server script suite.

readonly SUPPORTED_UBUNTU_RELEASES=("22.04" "24.04" "26.04")

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' is missing"
}

require_normal_user() {
  [[ $EUID -ne 0 ]] || die "run this script as the normal login user with sudo access, not root"
}

verify_supported_ubuntu() {
  local os_release=/etc/os-release supported=false release
  if [[ ${SERVER_SCRIPTS_TESTING:-0} == 1 && -n ${SERVER_SCRIPTS_OS_RELEASE_FILE:-} ]]; then
    os_release=$SERVER_SCRIPTS_OS_RELEASE_FILE
  fi
  [[ -r $os_release ]] || die "cannot read $os_release"

  local ID='' VERSION_ID='' PRETTY_NAME='unknown'
  # shellcheck source=/dev/null
  source "$os_release"
  [[ ${ID:-} == ubuntu ]] || die "this suite supports Ubuntu only; detected ${PRETTY_NAME:-unknown}"
  for release in "${SUPPORTED_UBUNTU_RELEASES[@]}"; do
    if [[ ${VERSION_ID:-} == "$release" ]]; then
      supported=true
      break
    fi
  done
  [[ $supported == true ]] || die "unsupported Ubuntu release '${VERSION_ID:-unknown}'; supported releases: ${SUPPORTED_UBUNTU_RELEASES[*]}"
}

init_sudo() {
  require_command sudo
  if [[ ${DRY_RUN:-false} != true ]]; then
    sudo -v || die "sudo authentication failed"
  fi
}

print_command() {
  printf '[dry-run]'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if [[ ${DRY_RUN:-false} == true ]]; then
    print_command "$@"
    return 0
  fi
  "$@"
}

run_optional() {
  if ! run "$@"; then
    warn "command failed: $*"
    FAILURES=$((FAILURES + 1))
  fi
}

confirm_yes() {
  local prompt=$1 answer
  read -r -p "$prompt [y/N]: " answer
  [[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]]
}

remove_managed_block() {
  local file=$1 start=$2 end=$3 temp_file
  [[ -f $file ]] || return 0
  temp_file=$(mktemp)
  awk -v start="$start" -v end="$end" '
    $0 == start { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$file" >"$temp_file"
  chmod --reference="$file" "$temp_file"
  mv "$temp_file" "$file"
}

finish_with_failures() {
  local activity=$1
  if ((FAILURES > 0)); then
    die "$activity completed with $FAILURES failure(s); review the warnings above"
  fi
}
