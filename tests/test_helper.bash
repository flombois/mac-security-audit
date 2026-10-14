# Shared test vocabulary: stub commands on PATH, a throwaway HOME, and result lookups.

ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

# Usage: setup_audit checks/NN-section.sh
setup_audit() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"
  export AUDIT_SYSTEM_PATH="$STUB_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export INVENTORY_APP_DIRS="$BATS_TEST_TMPDIR/Applications"
  export HOMEBREW_PREFIXES="$BATS_TEST_TMPDIR/homebrew"
  export JAVA_VM_DIR="$BATS_TEST_TMPDIR/JavaVirtualMachines"
  export PYTHON_ORG_DIR="$BATS_TEST_TMPDIR/Python.framework/Versions"
  export GO_INSTALL_DIR="$BATS_TEST_TMPDIR/go"
  export N_PREFIX="$BATS_TEST_TMPDIR/n-prefix"
  mkdir -p "$INVENTORY_APP_DIRS"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  unset KUBECONFIG GNUPGHOME NO_COLOR GRADLE_USER_HOME NPM_CONFIG_USERCONFIG npm_config_ignore_scripts NPM_CONFIG_IGNORE_SCRIPTS
  source "$ROOT_DIR/lib/system.sh"
  source "$ROOT_DIR/lib/report.sh"
  source "$ROOT_DIR/lib/progress.sh"
  source "$ROOT_DIR/lib/runner.sh"
  source "$ROOT_DIR/lib/inventory.sh"
  source "$ROOT_DIR/lib/runtimes.sh"
  source "$ROOT_DIR/lib/https.sh"
  source "$ROOT_DIR/lib/endoflife.sh"
  source "$ROOT_DIR/$1"
  report_init false
  stub_no_sudo
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

# Usage: given_app name bundle_id [version] [folder]
given_app() {
  local plist="${4:-$INVENTORY_APP_DIRS}/$1.app/Contents/Info.plist"
  mkdir -p "$(dirname "$plist")"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleIdentifier -string "$2" "$plist"
  [[ -z "${3:-}" ]] || plutil -insert CFBundleShortVersionString -string "$3" "$plist"
}

# Makes sudo run commands as if `sudo -v` had cached credentials.
given_cached_sudo() {
  stub_script sudo <<'EOF'
[[ "$1" == -n ]] && shift
"$@"
EOF
}

# Makes sudo refuse to run without a password.
stub_no_sudo() {
  stub_command sudo "sudo: a password is required" 1
}

# Prints "pass", "fail <severity>", "skipped" or "error".
result_of() {
  jq -r --arg id "$1" 'select(.id == $id) | if .status == "run" then [.outcome, .severity // empty] | join(" ") else .status end' \
    "$RESULTS_FILE"
}

detail_of() {
  jq -r --arg id "$1" 'select(.id == $id) | .detail' "$RESULTS_FILE"
}

# Prints a "YYYY-MM-DD HH:MM:SS" date $1 days ago.
days_ago() {
  date -v-"$1"d '+%Y-%m-%d %H:%M:%S'
}
