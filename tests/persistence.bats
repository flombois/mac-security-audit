#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/40-persistence.sh
  SYSTEM_LAUNCH_DIRS="$BATS_TEST_TMPDIR/LaunchDaemons"
  mkdir -p "$SYSTEM_LAUNCH_DIRS" "$HOME/Library/LaunchAgents"
  stub_no_sudo
}

# Usage: given_launch_item label program
given_launch_item() {
  local plist="$SYSTEM_LAUNCH_DIRS/$1.plist"
  plutil -create xml1 "$plist"
  plutil -insert Label -string "$1" "$plist"
  plutil -insert ProgramArguments -array "$plist"
  plutil -insert ProgramArguments.0 -string "$2" "$plist"
}

@test "launch item running a signed program passes" {
  given_launch_item com.example.signed /bin/ls

  run check_persistence_launch_items

  [[ "$(status_of persistence.launch-items)" == pass ]]
}

@test "launch item whose program is gone warns" {
  given_launch_item com.example.leftover /Applications/Gone.app/Contents/MacOS/gone

  run check_persistence_launch_items

  [[ "$(detail_of persistence.launch-items)" == "com.example.leftover: program missing (/Applications/Gone.app/Contents/MacOS/gone)" ]]
}

@test "launch item running a script warns" {
  given_launch_item com.example.script /bin/sh

  run check_persistence_launch_items

  [[ "$(detail_of persistence.launch-items)" == "com.example.script: runs a script through sh" ]]
}

@test "launch item running an unsigned program warns" {
  printf '#!/bin/sh\necho hi\n' >"$BATS_TEST_TMPDIR/helper"
  chmod +x "$BATS_TEST_TMPDIR/helper"
  given_launch_item com.example.unsigned "$BATS_TEST_TMPDIR/helper"

  run check_persistence_launch_items

  [[ "$(status_of persistence.launch-items)" == warn ]]
}

@test "launch item without a program is noted, not warned" {
  plutil -create xml1 "$HOME/Library/LaunchAgents/com.example.empty.plist"

  run check_persistence_launch_items

  [[ "$(detail_of persistence.launch-items)" == "1 item(s); com.example.empty: no program set" ]]
}

@test "Apple launch items are ignored" {
  given_launch_item com.apple.something /Applications/Gone.app/Contents/MacOS/gone

  run check_persistence_launch_items

  [[ "$(detail_of persistence.launch-items)" == "0 item(s)" ]]
}

@test "settings that need a human are listed for manual review" {
  run check_persistence_manual_reviews

  [[ "$(jq -s '[.[] | select(.status == "manual")] | length' "$RESULTS_FILE")" -eq 4 ]]
}
