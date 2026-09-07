#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT_DIR
PASSED=0
FAILED=0

pass() {
  printf 'PASS: %s\n' "$1"
  PASSED=$((PASSED + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILED=$((FAILED + 1))
}

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  if [[ $haystack == *"$needle"* ]]; then pass "$message"; else fail "$message"; fi
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  if [[ $haystack != *"$needle"* ]]; then pass "$message"; else fail "$message"; fi
}

make_os_release() {
  local path=$1 id=$2 version=$3
  cat >"$path" <<EOF
ID=$id
VERSION_ID="$version"
PRETTY_NAME="Test OS"
VERSION_CODENAME=test
UBUNTU_CODENAME=test
EOF
}

make_docker_mock() {
  local bin_dir=$1
  mkdir -p "$bin_dir"
  cat >"$bin_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_LOG"
case "$*" in
  info) exit 0 ;;
  "context show") echo default ;;
  "container ls --all --quiet") printf 'running123\nstopped456\n' ;;
  "image ls --all --quiet") printf 'image123\nimage123\nimage456\n' ;;
  "volume ls --quiet") printf 'volume123\n' ;;
  "network ls --quiet --filter type=custom --filter scope=local") printf 'network123\n' ;;
  "network inspect --format {{len .Containers}} network123") echo 0 ;;
esac
EOF
  chmod +x "$bin_dir/docker"
}

test_os_validation() {
  local temp ubuntu_file debian_file output
  temp=$(mktemp -d)
  ubuntu_file="$temp/ubuntu"
  debian_file="$temp/debian"
  make_os_release "$ubuntu_file" ubuntu 24.04
  make_os_release "$debian_file" debian 12

  SERVER_SCRIPTS_TESTING=1 SERVER_SCRIPTS_OS_RELEASE_FILE="$ubuntu_file" \
    TEST_ROOT_DIR="$ROOT_DIR" bash -c 'source "$TEST_ROOT_DIR/lib/common.sh"; verify_supported_ubuntu'
  pass "supported Ubuntu release is accepted"

  if output=$(SERVER_SCRIPTS_TESTING=1 SERVER_SCRIPTS_OS_RELEASE_FILE="$debian_file" \
    TEST_ROOT_DIR="$ROOT_DIR" bash -c 'source "$TEST_ROOT_DIR/lib/common.sh"; verify_supported_ubuntu' 2>&1); then
    fail "non-Ubuntu release is rejected"
  else
    assert_contains "$output" "supports Ubuntu only" "non-Ubuntu release is rejected"
  fi
  rm -rf -- "$temp"
}

test_alias_idempotency() {
  local temp alias_count loader_count
  temp=$(mktemp -d)
  cat >"$temp/.bash_aliases" <<'EOF'
keep-aliases
# >>> server-bootstrap aliases >>>
alias legacy='true'
# <<< server-bootstrap aliases <<<
EOF
  cat >"$temp/.bashrc" <<'EOF'
keep-bashrc
# >>> server-bootstrap bash_aliases loader >>>
. "$HOME/.bash_aliases"
# <<< server-bootstrap bash_aliases loader <<<
EOF

  HOME="$temp" bash "$ROOT_DIR/setup-aliases.sh" >/dev/null
  HOME="$temp" bash "$ROOT_DIR/setup-aliases.sh" >/dev/null

  alias_count=$(grep -c '^# >>> ubuntu-server-scripts aliases >>>$' "$temp/.bash_aliases")
  loader_count=$(grep -c '^# >>> ubuntu-server-scripts alias loader >>>$' "$temp/.bashrc")
  if [[ $alias_count == 1 ]]; then pass "alias block is idempotent"; else fail "alias block is idempotent"; fi
  if [[ $loader_count == 1 ]]; then pass "alias loader is idempotent"; else fail "alias loader is idempotent"; fi
  if grep -qx keep-aliases "$temp/.bash_aliases"; then pass "existing aliases are preserved"; else fail "existing aliases are preserved"; fi
  if grep -qx keep-bashrc "$temp/.bashrc"; then pass "existing bashrc content is preserved"; else fail "existing bashrc content is preserved"; fi
  if ! grep -q 'server-bootstrap' "$temp/.bash_aliases" "$temp/.bashrc"; then pass "legacy managed alias blocks are migrated"; else fail "legacy managed alias blocks are migrated"; fi
  rm -rf -- "$temp"
}

run_docker_case() {
  local input=$1 extra_arg=${2:-} temp os_file output status=0
  local -a args=()
  [[ -n $extra_arg ]] && args+=("$extra_arg")
  temp=$(mktemp -d)
  os_file="$temp/os-release"
  make_os_release "$os_file" ubuntu 24.04
  make_docker_mock "$temp/bin"
  : >"$temp/docker.log"

  output=$(printf '%b' "$input" | env \
    SERVER_SCRIPTS_TESTING=1 SERVER_SCRIPTS_OS_RELEASE_FILE="$os_file" \
    MOCK_LOG="$temp/docker.log" PATH="$temp/bin:$PATH" \
    bash "$ROOT_DIR/clean-docker.sh" "${args[@]}" 2>&1) || status=$?
  DOCKER_TEST_OUTPUT=$output
  DOCKER_TEST_LOG=$(<"$temp/docker.log")
  DOCKER_TEST_STATUS=$status
  rm -rf -- "$temp"
}

test_docker_modes() {
  run_docker_case '1\ny\n'
  assert_contains "$DOCKER_TEST_LOG" "container prune --force" "normal cleanup prunes stopped containers"
  assert_not_contains "$DOCKER_TEST_LOG" "container rm --force" "normal cleanup preserves running containers"
  assert_contains "$DOCKER_TEST_LOG" "network rm network123" "normal cleanup removes only unattached local custom networks"

  run_docker_case '2\nWRONG\n'
  if [[ $DOCKER_TEST_STATUS == 0 ]]; then pass "incorrect force phrase exits safely"; else fail "incorrect force phrase exits safely"; fi
  assert_not_contains "$DOCKER_TEST_LOG" "container rm --force" "incorrect force phrase performs no deletion"

  run_docker_case '2\nDELETE ALL DOCKER DATA\n'
  assert_contains "$DOCKER_TEST_LOG" "container rm --force running123 stopped456" "force cleanup removes running and stopped containers"
  assert_contains "$DOCKER_TEST_LOG" "image rm --force image123 image456" "force cleanup deduplicates and removes all images"
  assert_contains "$DOCKER_TEST_LOG" "network rm network123" "force cleanup targets local custom networks"
  assert_not_contains "$DOCKER_TEST_LOG" "service" "force cleanup does not target Swarm services"

  run_docker_case '2\n' --dry-run
  assert_contains "$DOCKER_TEST_OUTPUT" "[dry-run] docker container rm" "Docker dry run previews destructive commands"
  assert_not_contains "$DOCKER_TEST_LOG" "container rm --force" "Docker dry run performs no deletion"

  run_docker_case '9\n'
  if [[ $DOCKER_TEST_STATUS != 0 ]]; then pass "invalid Docker menu choice fails"; else fail "invalid Docker menu choice fails"; fi
  assert_not_contains "$DOCKER_TEST_LOG" "prune --force" "invalid Docker menu choice performs no cleanup"
}

test_safe_cleanup_dry_run() {
  local temp os_file output command
  temp=$(mktemp -d)
  os_file="$temp/os-release"
  make_os_release "$os_file" ubuntu 24.04
  mkdir -p "$temp/bin"
  for command in sudo apt-get journalctl systemd-tmpfiles; do
    cat >"$temp/bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$MOCK_LOG"
EOF
    chmod +x "$temp/bin/$command"
  done
  : >"$temp/commands.log"

  output=$(env SERVER_SCRIPTS_TESTING=1 SERVER_SCRIPTS_OS_RELEASE_FILE="$os_file" \
    MOCK_LOG="$temp/commands.log" PATH="$temp/bin:$PATH" \
    bash "$ROOT_DIR/clean-server.sh" --dry-run)
  assert_contains "$output" "[dry-run] sudo" "safe cleanup dry run previews privileged commands"
  if [[ ! -s $temp/commands.log ]]; then pass "safe cleanup dry run executes no mutating mock"; else fail "safe cleanup dry run executes no mutating mock"; fi
  rm -rf -- "$temp"
}

test_reset_targets_are_bounded() {
  local output
  output=$(TEST_ROOT_DIR="$ROOT_DIR" SERVER_SCRIPTS_LIBRARY_MODE=1 bash -c '
    source "$TEST_ROOT_DIR/reset-server.sh"
    DRY_RUN=true
    TARGET_USER=tester
    TARGET_HOME=/home/tester
    remove_user_development_state
  ')
  assert_contains "$output" "/home/tester/.docker" "reset dry run targets known Docker state"
  assert_contains "$output" "/home/tester/.gitconfig" "reset dry run targets global Git configuration"
  assert_not_contains "$output" "rm -rf -- /home/tester " "reset never recursively deletes the user home"
  assert_not_contains "$output" "/home/tester/.ssh" "reset never targets SSH data"
}

test_os_validation
test_alias_idempotency
test_docker_modes
test_safe_cleanup_dry_run
test_reset_targets_are_bounded

printf '\nTests passed: %d\nTests failed: %d\n' "$PASSED" "$FAILED"
((FAILED == 0))
