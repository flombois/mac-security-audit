#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/20-accounts.sh
}

@test "no automatic login passes" {
  stub_command defaults "The domain/default pair does not exist" 1

  run check_accounts_auto_login

  [[ "$(result_of accounts.auto-login)" == pass ]]
}

@test "automatic login fails and names the user" {
  stub_command defaults bob

  run check_accounts_auto_login

  [[ "$(detail_of accounts.auto-login)" == "logs in as bob without a password" ]]
}

@test "guest account on fails" {
  stub_command defaults 1

  run check_accounts_guest

  [[ "$(result_of accounts.guest)" == "fail medium" ]]
}

@test "guest account never configured passes" {
  stub_command defaults "The domain/default pair does not exist" 1

  run check_accounts_guest

  [[ "$(result_of accounts.guest)" == pass ]]
}

@test "screen lock after five minutes warns" {
  stub_command sysadminctl "2026-10-13 10:43:16.085 sysadminctl[18403:14622119] screenLock delay is 300 seconds"

  run check_accounts_screen_lock

  [[ "$(result_of accounts.screen-lock)" == "fail medium" ]]
}

@test "screen lock at once passes" {
  stub_command sysadminctl "2026-10-13 10:43:16.085 sysadminctl[1:2] screenLock delay is 0 seconds"

  run check_accounts_screen_lock

  [[ "$(result_of accounts.screen-lock)" == pass ]]
}

@test "screen lock immediate passes" {
  stub_command sysadminctl "2026-10-13 10:43:16.085 sysadminctl[1:2] screenLock delay is immediate"

  run check_accounts_screen_lock

  [[ "$(result_of accounts.screen-lock)" == pass ]]
}

@test "screen lock off fails" {
  stub_command sysadminctl "2026-10-13 10:43:16.085 sysadminctl[1:2] screenLock is off"

  run check_accounts_screen_lock

  [[ "$(result_of accounts.screen-lock)" == "fail high" ]]
}

@test "Touch ID for sudo passes when pam_tid is active" {
  SUDO_LOCAL_FILE="$BATS_TEST_TMPDIR/sudo_local"
  echo "auth       sufficient     pam_tid.so" >"$SUDO_LOCAL_FILE"

  run check_accounts_touch_id_sudo

  [[ "$(result_of accounts.touch-id-sudo)" == pass ]]
}

@test "Touch ID for sudo warns when pam_tid is commented out" {
  SUDO_LOCAL_FILE="$BATS_TEST_TMPDIR/sudo_local"
  echo "#auth       sufficient     pam_tid.so" >"$SUDO_LOCAL_FILE"

  run check_accounts_touch_id_sudo

  [[ "$(result_of accounts.touch-id-sudo)" == "fail low" ]]
}

@test "Touch ID for sudo warns without sudo_local" {
  SUDO_LOCAL_FILE="$BATS_TEST_TMPDIR/missing"

  run check_accounts_touch_id_sudo

  [[ "$(result_of accounts.touch-id-sudo)" == "fail low" ]]
}

@test "administrator daily account warns" {
  stub_script id <<'EOF'
[[ "$1" == -Gn ]] && echo "staff everyone admin _developer" || echo alice
EOF

  run check_accounts_admin

  [[ "$(result_of accounts.admin)" == "fail medium" ]]
}

@test "standard daily account passes" {
  stub_script id <<'EOF'
[[ "$1" == -Gn ]] && echo "staff everyone _appserveradm" || echo alice
EOF

  run check_accounts_admin

  [[ "$(result_of accounts.admin)" == pass ]]
}

@test "Activation Lock enabled passes" {
  stub_command system_profiler "      Activation Lock Status: Enabled"

  run check_accounts_find_my

  [[ "$(result_of accounts.find-my)" == pass ]]
}

@test "Activation Lock disabled warns" {
  stub_command system_profiler "      Activation Lock Status: Disabled"

  run check_accounts_find_my

  [[ "$(result_of accounts.find-my)" == "fail medium" ]]
}

@test "Activation Lock not reported is skipped" {
  stub_command system_profiler "      Model Identifier: MacBookPro16,1"

  run check_accounts_find_my

  [[ "$(result_of accounts.find-my)" == skipped ]]
}
