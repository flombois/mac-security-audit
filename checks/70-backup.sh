# Backup: Time Machine.

BACKUP_MAX_AGE_DAYS=7

run_backup_checks() {
  check_backup_destination
  check_backup_latest
  check_backup_manual_reviews
}

check_backup_destination() {
  local output names
  output="$(tmutil destinationinfo 2>&1)" || true
  names="$(echo "$output" | sed -n -E 's/^Name[[:space:]]*: //p' | join_lines)"
  if [[ -n "$names" ]]; then
    report_pass backup.destination "Time Machine destination configured" "$names"
  else
    report_fail backup.destination "Time Machine destination configured" "${output:-no destination}" \
      "System Settings › General › Time Machine: add an encrypted backup disk"
  fi
}

check_backup_latest() {
  local latest stamp age
  if ! latest="$(tmutil latestbackup 2>/dev/null)" || [[ "$latest" != /* ]]; then
    report_skip backup.latest "Recent Time Machine backup" \
      "no backup found, destination not mounted, or the terminal lacks Full Disk Access"
    return
  fi
  stamp="$(basename "$latest" | sed -n -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}).*/\1 \2:\3:\4/p')"
  if ! age="$(days_since "$stamp")"; then
    report_info backup.latest "Recent Time Machine backup" "latest: $(basename "$latest")"
  elif [[ "$age" -gt "$BACKUP_MAX_AGE_DAYS" ]]; then
    report_warn backup.latest "Recent Time Machine backup" "last backup $age days ago" \
      "Connect the backup disk, or run: tmutil startbackup"
  else
    report_pass backup.latest "Recent Time Machine backup" "last backup $age day(s) ago"
  fi
}

check_backup_manual_reviews() {
  report_manual backup.encryption "Backups encrypted, with an off-site copy" \
    "System Settings › General › Time Machine › Options: check 'Encrypt backup'; keep a second copy off-site or in the cloud"
  report_manual backup.restore-test "Restore tested" \
    "Restore a few files from the latest backup to confirm it works"
}
