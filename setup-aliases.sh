#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly ALIASES_FILE="$HOME/.bash_aliases"
readonly BASHRC_FILE="$HOME/.bashrc"
readonly ALIASES_START="# >>> ubuntu-server-scripts aliases >>>"
readonly ALIASES_END="# <<< ubuntu-server-scripts aliases <<<"
readonly LOADER_START="# >>> ubuntu-server-scripts alias loader >>>"
readonly LOADER_END="# <<< ubuntu-server-scripts alias loader <<<"
readonly LEGACY_ALIASES_START="# >>> server-bootstrap aliases >>>"
readonly LEGACY_ALIASES_END="# <<< server-bootstrap aliases <<<"
readonly LEGACY_LOADER_START="# >>> server-bootstrap bash_aliases loader >>>"
readonly LEGACY_LOADER_END="# <<< server-bootstrap bash_aliases loader <<<"

trap 'echo "Error: alias setup failed on line $LINENO." >&2' ERR

usage() {
  echo "Usage: ${0##*/}"
  echo "Install the managed Git, Docker, and Compose Bash aliases."
}

main() {
  case ${1:-} in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac

  require_normal_user
  require_command awk
  require_command mktemp

  touch "$ALIASES_FILE" "$BASHRC_FILE"
  remove_managed_block "$ALIASES_FILE" "$ALIASES_START" "$ALIASES_END"
  remove_managed_block "$BASHRC_FILE" "$LOADER_START" "$LOADER_END"
  remove_managed_block "$ALIASES_FILE" "$LEGACY_ALIASES_START" "$LEGACY_ALIASES_END"
  remove_managed_block "$BASHRC_FILE" "$LEGACY_LOADER_START" "$LEGACY_LOADER_END"

  cat >>"$ALIASES_FILE" <<'EOF'
# >>> ubuntu-server-scripts aliases >>>
# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline --graph --decorate'
alias gco='git checkout'
alias gb='git branch'

# Docker
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps --all'
alias di='docker images'
alias dex='docker exec -it'
alias dl='docker logs --follow'

# Docker Compose
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcp='docker compose ps'
alias dcb='docker compose build'
# <<< ubuntu-server-scripts aliases <<<
EOF

  cat >>"$BASHRC_FILE" <<'EOF'
# >>> ubuntu-server-scripts alias loader >>>
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi
# <<< ubuntu-server-scripts alias loader <<<
EOF

  log "Aliases installed in $ALIASES_FILE."
  log "Run 'source ~/.bashrc' or start a new Bash session to activate them."
}

if [[ ${SERVER_SCRIPTS_LIBRARY_MODE:-0} != 1 ]]; then
  main "$@"
fi
