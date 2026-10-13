# Shared test vocabulary: stub commands on PATH, a throwaway HOME, and result lookups.

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

# Usage: setup_audit checks/NN-section.sh
setup_audit() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  unset KUBECONFIG GNUPGHOME NO_COLOR
  source "$ROOT_DIR/lib/system.sh"
  source "$ROOT_DIR/lib/report.sh"
  source "$ROOT_DIR/$1"
  report_init false
}

# Usage: stub_command name output [exit_status]
# The stub prints the output whatever its arguments are: to stdout on success, to stderr on failure.
stub_command() {
  local exit_status="${3:-0}" redirect=""
  [[ "$exit_status" -eq 0 ]] || redirect=">&2"
  printf '%s\n' "$2" >"$STUB_DIR/$1.out"
  stub_script "$1" <<EOF
cat "$STUB_DIR/$1.out" $redirect
exit $exit_status
EOF
}

# Usage: stub_script name <<'EOF' ... EOF
# The stub runs the bash body read from stdin; "\$*" holds its arguments.
stub_script() {
  {
    echo '#!/bin/bash'
    cat
  } >"$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

# Makes sudo refuse to run without a password.
stub_no_sudo() {
  stub_command sudo "sudo: a password is required" 1
}

status_of() {
  jq -r --arg id "$1" 'select(.id == $id) | .status' "$RESULTS_FILE"
}

detail_of() {
  jq -r --arg id "$1" 'select(.id == $id) | .detail' "$RESULTS_FILE"
}

# Prints a "YYYY-MM-DD HH:MM:SS" date $1 days ago.
days_ago() {
  date -v-"$1"d '+%Y-%m-%d %H:%M:%S'
}
