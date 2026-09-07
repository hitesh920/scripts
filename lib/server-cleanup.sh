#!/usr/bin/env bash

# Safe cleanup routines shared by clean-server.sh and reset-server.sh.

show_disk_summary() {
  log "Filesystem usage:"
  df -h /
  log "Known cleanup targets (unreadable paths are omitted):"
  du -sh /var/cache/apt/archives /var/log/journal /var/crash 2>/dev/null || true
}

clean_apt_data() {
  log "Removing unused packages and apt caches..."
  run_optional sudo env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
  run_optional sudo apt-get autoclean
  run_optional sudo apt-get clean
}

clean_disabled_snaps() {
  command -v snap >/dev/null 2>&1 || return 0

  local name revision
  local -a disabled=()
  mapfile -t disabled < <(LC_ALL=C snap list --all 2>/dev/null | awk '$NF == "disabled" { print $1 " " $3 }')
  if ((${#disabled[@]} == 0)); then
    log "No disabled Snap revisions found."
    return 0
  fi

  log "Removing disabled Snap revisions..."
  for entry in "${disabled[@]}"; do
    read -r name revision <<<"$entry"
    run_optional sudo snap remove "$name" --revision="$revision"
  done
}

clean_crash_dumps() {
  [[ -d /var/crash ]] || return 0

  local -a crash_entries=()
  mapfile -d '' -t crash_entries < <(
    find /var/crash -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print0 2>/dev/null
  )
  if ((${#crash_entries[@]})); then
    log "Removing crash dump files from /var/crash..."
    run_optional sudo rm -f -- "${crash_entries[@]}"
  else
    log "No crash dump files found."
  fi
}

clean_journal_and_temporary_files() {
  log "Keeping 14 days of system journal entries..."
  run_optional sudo journalctl --vacuum-time=14d
  log "Applying systemd's configured temporary-file retention policies..."
  run_optional sudo systemd-tmpfiles --clean
}

perform_safe_cleanup() {
  clean_apt_data
  clean_disabled_snaps
  clean_crash_dumps
  clean_journal_and_temporary_files
}
