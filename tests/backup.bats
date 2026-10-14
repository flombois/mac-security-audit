#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/70-backup.sh
}

# Usage: given_latest_backup_days_ago days
given_latest_backup_days_ago() {
  local stamp
  stamp="$(date -v-"$1"d '+%Y-%m-%d-%H%M%S')"
  stub_command tmutil "/Volumes/Backups/$stamp.previous"
}

@test "no Time Machine destination fails" {
  stub_command tmutil "tmutil: No destinations configured."

  run check_backup_destination

  [[ "$(result_of backup.destination)" == "fail high" ]]
}

@test "Time Machine destination passes and is named" {
  stub_command tmutil $'====================================================\nName          : Backup Disk\nKind          : Local\nID            : 1234'

  run check_backup_destination

  [[ "$(detail_of backup.destination)" == "Backup Disk" ]]
}

@test "recent backup passes" {
  given_latest_backup_days_ago 1

  run check_backup_latest

  [[ "$(result_of backup.latest)" == pass ]]
}

@test "old backup warns" {
  given_latest_backup_days_ago 30

  run check_backup_latest

  [[ "$(detail_of backup.latest)" == "last backup 30 days ago" ]]
}

@test "unreadable latest backup is skipped" {
  stub_command tmutil "Failed to mount backup destination" 1

  run check_backup_latest

  [[ "$(result_of backup.latest)" == skipped ]]
}

@test "latest backup answer that is not a path is skipped" {
  stub_command tmutil "tmutil: No destinations configured."

  run check_backup_latest

  [[ "$(result_of backup.latest)" == skipped ]]
}
