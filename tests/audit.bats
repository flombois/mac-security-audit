#!/usr/bin/env bats

load test_helper

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

@test "missing scan directory is a usage error" {
  run "$ROOT_DIR/audit.sh" --scan-repos "$BATS_TEST_TMPDIR/nowhere"

  [[ "$status" -eq 2 ]]
}

@test "audit without failures exits 0" {
  given_backups_configured

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$status" -eq 0 ]]
}

@test "audit with a failure exits 1" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$status" -eq 1 ]]
}

@test "only the selected section runs" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup

  [[ "$output" != *"== platform"* ]]
}

@test "JSON report summarises the checks" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup --json "$BATS_TEST_TMPDIR/report.json"

  [[ "$(jq -c .summary "$BATS_TEST_TMPDIR/report.json")" == '{"pass":0,"warn":0,"fail":1,"info":0,"skip":1,"manual":2}' ]]
}

@test "JSON report is pretty-printed" {
  given_no_backups

  run "$ROOT_DIR/audit.sh" --no-color --section backup --json "$BATS_TEST_TMPDIR/report.json"

  [[ "$(wc -l <"$BATS_TEST_TMPDIR/report.json")" -gt 10 ]]
}

# Runs the audit on a pseudo-terminal, as a person would; fails if it did not run.
run_audit_on_terminal() {
  run script -q /dev/null "$ROOT_DIR/audit.sh" "$@" </dev/null
  [[ "$output" == *"== backup"* ]]
}

@test "output on a terminal is coloured" {
  given_no_backups

  run_audit_on_terminal --section backup

  [[ "$output" == *$'\033['* ]]
}

@test "NO_COLOR turns colour off on a terminal" {
  given_no_backups
  export NO_COLOR=1

  run_audit_on_terminal --section backup

  [[ "$output" != *$'\033['* ]]
}

@test "--no-color turns colour off on a terminal" {
  given_no_backups

  run_audit_on_terminal --no-color --section backup

  [[ "$output" != *$'\033['* ]]
}
