# Accounts: login, screen lock and recovery.

LOGIN_WINDOW_PREFS=/Library/Preferences/com.apple.loginwindow
SCREEN_LOCK_MAX_DELAY_SECONDS=5

run_accounts_checks() {
  run_check "automatic login" check_accounts_auto_login
  run_check "guest account" check_accounts_guest
  run_check "screen lock" check_accounts_screen_lock
  run_check "Touch ID for sudo" check_accounts_touch_id_sudo
  run_check "admin rights" check_accounts_admin
  run_check "Find My" check_accounts_find_my
}

check_accounts_auto_login() {
  local user
  if user="$(defaults read "$LOGIN_WINDOW_PREFS" autoLoginUser 2>/dev/null)"; then
    report_fail accounts.auto-login high "Automatic login off" "logs in as $user without a password" \
      "System Settings › Users & Groups › Automatically log in as: Off"
  else
    report_pass accounts.auto-login "Automatic login off"
  fi
}

check_accounts_guest() {
  local enabled
  enabled="$(defaults read "$LOGIN_WINDOW_PREFS" GuestEnabled 2>/dev/null)" || enabled=0
  if [[ "$enabled" == 1 ]]; then
    report_fail accounts.guest medium "Guest account off" "GuestEnabled=1" \
      "System Settings › Users & Groups › Guest User: turn off"
  else
    report_pass accounts.guest "Guest account off"
  fi
}

check_accounts_screen_lock() {
  local output delay
  output="$(sysadminctl -screenLock status 2>&1)" || true
  delay="$(echo "$output" | sed -n -E 's/.*screenLock delay is ([0-9]+) seconds.*/\1/p')"
  local title="Password required at once after sleep or screen saver"
  local remediation="System Settings › Lock Screen › Require password after screen saver begins or display is turned off: Immediately"
  if [[ "$output" == *"screenLock is off"* ]]; then
    report_fail accounts.screen-lock high "$title" "no password required" "$remediation"
  elif [[ "$output" == *immediate* ]]; then
    report_pass accounts.screen-lock "$title"
  elif [[ -z "$delay" ]]; then
    report_error accounts.screen-lock "$title" "could not read: $output"
  elif [[ "$delay" -le "$SCREEN_LOCK_MAX_DELAY_SECONDS" ]]; then
    report_pass accounts.screen-lock "$title" "after $delay seconds"
  else
    report_fail accounts.screen-lock medium "$title" "only after $delay seconds" "$remediation"
  fi
}

check_accounts_touch_id_sudo() {
  if grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$SUDO_LOCAL_FILE" 2>/dev/null; then
    report_pass accounts.touch-id-sudo "Touch ID for sudo"
  else
    report_fail accounts.touch-id-sudo low "Touch ID for sudo" \
      "sudo asks for the password, which then gets typed into terminals" \
      "sudo sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local"
  fi
}

check_accounts_admin() {
  if id -Gn | tr ' ' '\n' | grep -qx admin; then
    report_fail accounts.admin medium "Daily account is not an administrator" "$(id -un) is in the admin group" \
      "Optional: create a separate admin account and make this one a standard user"
  else
    report_pass accounts.admin "Daily account is not an administrator"
  fi
}

check_accounts_find_my() {
  local status
  status="$(system_profiler SPHardwareDataType 2>/dev/null | sed -n -E 's/.*Activation Lock Status: (.*)/\1/p')"
  case "$status" in
    Enabled)
      report_pass accounts.find-my "Find My Mac and Activation Lock on" ;;
    "")
      report_skip accounts.find-my "Find My Mac and Activation Lock on" "Activation Lock status not reported on this Mac" ;;
    *)
      report_fail accounts.find-my medium "Find My Mac and Activation Lock on" "Activation Lock: $status" \
        "System Settings › Apple Account › iCloud › Find My Mac: turn on" ;;
  esac
}
