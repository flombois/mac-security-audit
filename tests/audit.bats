#!/usr/bin/env bats

load test_helper
bats_require_minimum_version 1.5.0

setup() {
  setup_audit checks/70-backup.sh
}

given_backups_configured() {
  stub_script tmutil <<'EOF'
case "$1" in
  destinationinfo) echo "Name          : Backup Disk" ;;
  latestbackup) echo "/Volumes/Backups/$(date '+%Y-%m-%d-%H%M%S').previous" ;;
esac
EOF
}

given_no_backups() {
  stub_script tmutil <<'EOF'
case "$1" in
  destinationinfo) echo "tmutil: No destinations configured." ;;
  latestbackup) echo "Failed to mount backup destination" >&2; exit 1 ;;
esac
EOF
}

# A backup destination; tmutil also notes the folder and umask it runs with.
given_backups_noting_where_they_run() {
  stub_script tmutil <<EOF
pwd >"$BATS_TEST_TMPDIR/tmutil.pwd"
umask >"$BATS_TEST_TMPDIR/tmutil.umask"
echo "Name          : Backup Disk"
EOF
}

# A backup destination with a 30-day-old backup: one medium finding.
given_old_backup() {
  stub_script tmutil <<'EOF'
case "$1" in
  destinationinfo) echo "Name          : Backup Disk" ;;
  latestbackup) echo "/Volumes/Backups/$(date -v-30d '+%Y-%m-%d-%H%M%S').previous" ;;
esac
EOF
}

@test "help exits successfully" {
  run "$ROOT_DIR/audit.sh" --help

  [[ "$status" -eq 0 ]]
}

@test "unknown option is a usage error" {
  run "$ROOT_DIR/audit.sh" --frobnicate

  [[ "$status" -eq 2 ]]
}

@test "unknown section is a usage error" {
  run "$ROOT_DIR/audit.sh" --section kitchen

  [[ "$status" -eq 2 ]]
}

@test "audit without a high-severity finding exits 0" {
  given_backups_configured

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$status" -eq 0 ]]
}

@test "audit with only lower-severity findings exits 0" {
  given_old_backup

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$status" -eq 0 && "$output" == *"MEDIUM"* ]]
}

@test "audit with a high-severity finding exits 1" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$status" -eq 1 ]]
}

@test "--exit-code=MEDIUM exits 1 on a medium finding" {
  given_old_backup

  run "$ROOT_DIR/audit.sh" --no-color --section backup --exit-code=MEDIUM

  [[ "$status" -eq 1 ]]
}

@test "--exit-code LOW exits 1 on a medium finding" {
  given_old_backup

  run "$ROOT_DIR/audit.sh" --no-color --section backup --exit-code LOW

  [[ "$status" -eq 1 ]]
}

@test "--exit-code=HIGH exits 0 on a medium finding" {
  given_old_backup

  run "$ROOT_DIR/audit.sh" --no-color --section backup --exit-code=HIGH

  [[ "$status" -eq 0 ]]
}

@test "--exit-code accepts lower case" {
  given_old_backup

  run "$ROOT_DIR/audit.sh" --no-color --section backup --exit-code=medium

  [[ "$status" -eq 1 ]]
}

@test "unknown --exit-code level is a usage error" {
  run "$ROOT_DIR/audit.sh" --exit-code=CRITICAL

  [[ "$status" -eq 2 && "$output" == *"unknown --exit-code: CRITICAL"* ]]
}

@test "only the selected section runs" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$output" != *platform* ]]
}

@test "JSON report summarises the checks" {
  given_no_backups

  run --separate-stderr "$ROOT_DIR/audit.sh" --no-color --section backup --json

  [[ "$(jq -c .summary <<<"$output")" == '{"status":{"run":2,"skipped":3,"error":0},"outcome":{"pass":1,"fail":1},"severity":{"high":1,"medium":0,"low":0}}' ]]
}

@test "JSON report is pretty-printed" {
  given_no_backups

  run --separate-stderr "$ROOT_DIR/audit.sh" --no-color --section backup --json

  [[ "${#lines[@]}" -gt 10 ]]
}

@test "with --json, stdout holds only the JSON report" {
  given_no_backups

  run --separate-stderr "$ROOT_DIR/audit.sh" --no-color --section backup --json

  jq -e .checks <<<"$output" >/dev/null
}

@test "--json and --interactive are a usage error together" {
  run "$ROOT_DIR/audit.sh" --json --interactive

  [[ "$status" -eq 2 ]]
}

@test "checks run from /, whatever the current folder" {
  given_backups_noting_where_they_run
  cd "$BATS_TEST_TMPDIR"

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$(cat "$BATS_TEST_TMPDIR/tmutil.pwd")" == / ]]
}

@test "files the audit creates are yours only" {
  given_backups_noting_where_they_run

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$(cat "$BATS_TEST_TMPDIR/tmutil.umask")" == 0077 ]]
}

# True when $1 holds colour escape codes; the progress line's erase code does not count.
has_colour() {
  [[ "$1" =~ $'\033'\[[0-9]+m ]]
}

# Runs the audit on a pseudo-terminal, as a person would; fails if it did not run.
run_audit_on_terminal() {
  run script -q /dev/null "$ROOT_DIR/audit.sh" "$@" </dev/null
  [[ "$output" == *"Findings ("* ]]
}

@test "output on a terminal is coloured" {
  given_no_backups

  run_audit_on_terminal --section backup

  has_colour "$output"
}

@test "NO_COLOR turns colour off on a terminal" {
  given_no_backups
  export NO_COLOR=1

  run_audit_on_terminal --section backup

  ! has_colour "$output"
}

@test "--no-color turns colour off on a terminal" {
  given_no_backups

  run_audit_on_terminal --no-color --section backup

  ! has_colour "$output"
}

@test "the report is framed on a terminal" {
  given_no_backups

  run_audit_on_terminal --no-color --section backup

  [[ "$output" == *"╭─ Findings ("*"╰─"* ]]
}

@test "the report is plain when piped" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --section backup

  [[ "$output" == *" Findings ("* && "$output" != *╭* ]]
}

@test "running checks are named on a terminal" {
  given_no_backups
  stub_script tmutil <<'STUB'
sleep 0.3
echo "tmutil: No destinations configured."
STUB

  run_audit_on_terminal --section backup

  [[ "$output" == *" backup.destination "* ]]
}

@test "--interactive needs a terminal" {
  run "$ROOT_DIR/audit.sh" --interactive --section backup

  [[ "$status" -eq 2 && "$output" == *"--interactive needs a terminal"* ]]
}

@test "no progress when stderr is not a terminal" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --section backup

  [[ "$output" != *Auditing* ]]
}

@test "--verify-apps is accepted" {
  given_backups_configured

  run "$ROOT_DIR/audit.sh" --no-color --verify-apps --section backup

  [[ "$status" -eq 0 ]]
}

# sudo acts as if credentials were cached and logs each call; the root-only tools are stubbed.
given_logged_sudo() {
  SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  stub_script sudo <<STUB
echo "\$*" >>"$SUDO_LOG"
[[ "\$1" == -n ]] && shift
[[ "\$1" == -k ]] || "\$@"
STUB
  stub_command bputil "Security Mode: Full Security"
  stub_command sfltool ""
  stub_command profiles ""
}

@test "sudo is dropped after its last use" {
  given_logged_sudo
  given_backups_configured
  stub_command curl "offline" 7

  run "$ROOT_DIR/audit.sh" --no-color

  [[ "$(tail -1 "$SUDO_LOG")" == -k ]]
}
