#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/40-persistence.sh
  SYSTEM_LAUNCH_DIRS="$BATS_TEST_TMPDIR/LaunchDaemons"
  mkdir -p "$SYSTEM_LAUNCH_DIRS" "$HOME/Library/LaunchAgents"
  stub_no_sudo
  stub_command pluginkit "  (no matches)"
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

  [[ "$(result_of persistence.launch-items)" == pass ]]
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

  [[ "$(result_of persistence.launch-items)" == "fail medium" ]]
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
  run check_persistence_privacy_permissions
  run check_persistence_accessories

  [[ "$(jq -s '[.[] | select(.detail == "to review yourself")] | length' "$RESULTS_FILE")" -eq 2 ]]
}

# The fixture's system items are fine; this user's include a leftover and an unsigned agent.
given_background_items() {
  sed -e "s/CURRENT_UID/$(id -u)/" -e "s/OTHER_UID/$(($(id -u) + 1))/" \
    "$FIXTURES_DIR/sfltool-dumpbtm.txt" >"$STUB_DIR/sfltool.out"
  stub_script sfltool <<EOF
touch "$STUB_DIR/sfltool.ran"
cat "$STUB_DIR/sfltool.out"
EOF
  given_cached_sudo
}

given_only_system_background_items() {
  given_background_items
  sed -i '' '/Records for UID [0-9]/,$d' "$STUB_DIR/sfltool.out"
}

@test "background item whose program is gone warns" {
  given_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" == *"OldAgent: program missing (/Library/Gone/OldAgent)"* ]]
}

@test "background item without a Team ID warns" {
  given_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" == *"SketchyAgent: no Team ID"* ]]
}

@test "Apple background items need no Team ID" {
  given_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" != *PasswordsMenuBarExtra* ]]
}

@test "disabled background items are ignored" {
  given_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" != *DisabledAgent* ]]
}

@test "other users' background items are ignored" {
  given_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" != *OtherUserAgent* ]]
}

@test "known background items are counted by developer" {
  given_only_system_background_items

  run check_persistence_login_items

  [[ "$(detail_of persistence.login-items)" == "2 enabled: Example Corp (1), TeamsAgent (1)" ]]
}

@test "background items are not read without sudo" {
  given_background_items
  stub_no_sudo

  run check_persistence_login_items

  [[ ! -e "$STUB_DIR/sfltool.ran" ]]
}

@test "background items are skipped without sudo" {
  given_background_items
  stub_no_sudo

  run check_persistence_login_items

  [[ "$(result_of persistence.login-items)" == skipped ]]
}

# Usage: given_chrome_extension profile_name name location [disable_reasons] [installed_by_default]
given_chrome_extension() {
  local chrome_dir="$HOME/Library/Application Support/Google/Chrome" settings
  mkdir -p "$chrome_dir/Default"
  [[ -e "$chrome_dir/Local State" ]] || echo "{\"profile\": {\"info_cache\": {\"Default\": {\"name\": \"$1\"}}}}" >"$chrome_dir/Local State"
  [[ -e "$chrome_dir/Default/Preferences" ]] || echo '{}' >"$chrome_dir/Default/Preferences"
  settings="$chrome_dir/Default/Secure Preferences"
  [[ -e "$settings" ]] || echo '{"extensions": {"settings": {}}}' >"$settings"
  jq --arg name "$2" --argjson location "$3" --argjson reasons "${4:-[]}" --argjson by_default "${5:-false}" \
    '.extensions.settings[$name] = {manifest: {name: $name}, location: $location,
      disable_reasons: $reasons, was_installed_by_default: $by_default}' "$settings" >"$settings.new"
  mv "$settings.new" "$settings"
}

# Usage: given_firefox_extension name location active
given_firefox_extension() {
  local profile_dir="$HOME/Library/Application Support/Firefox/Profiles/abcd1234.default-release"
  mkdir -p "$profile_dir"
  [[ -e "$profile_dir/extensions.json" ]] || echo '{"addons": []}' >"$profile_dir/extensions.json"
  jq --arg name "$1" --arg location "$2" --argjson active "$3" \
    '.addons += [{id: ($name + "@example.com"), type: "extension", location: $location,
      active: $active, defaultLocale: {name: $name}}]' "$profile_dir/extensions.json" >"$profile_dir/new.json"
  mv "$profile_dir/new.json" "$profile_dir/extensions.json"
}

@test "Chrome extensions are listed under their profile" {
  given_chrome_extension Work "uBlock Origin Lite" 1
  given_chrome_extension Work "iCloud Passwords" 1

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "Chrome (Work): iCloud Passwords, uBlock Origin Lite" ]]
}

@test "extensions that ship with Chrome are not listed" {
  given_chrome_extension Work "Chrome PDF Viewer" 5
  given_chrome_extension Work "Chrome Web Store Payments" 10
  given_chrome_extension Work "Google Docs Offline" 6 "[]" true

  run check_persistence_browser_extensions

  [[ "$(result_of persistence.browser-extensions)" == pass ]]
}

@test "turned off Chrome extensions are marked" {
  given_chrome_extension Work "Old Helper" 1 "[1]"

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "Chrome (Work): Old Helper (off)" ]]
}

@test "extension loaded from a folder warns" {
  given_chrome_extension Work "My Dev Extension" 4

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "loaded from a folder, never updated: Chrome (Work): My Dev Extension" ]]
}

@test "Firefox extensions you installed are listed" {
  given_firefox_extension "Multi-Account Containers" app-profile true
  given_firefox_extension "Form Autofill" app-system-defaults true

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "Firefox (default-release): Multi-Account Containers" ]]
}

@test "Safari extensions are named after their app" {
  stub_command pluginkit "$(printf '+    com.example.safari.ext(1.0)\tUUID\t2026-10-01 10:00:00 +0000\t/Applications/Example Blocker.app/Contents/PlugIns/Ext.appex')"

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "Safari: Example Blocker" ]]
}

@test "extensions are listed browser by browser" {
  given_chrome_extension Work "uBlock Origin Lite" 1
  given_firefox_extension "Multi-Account Containers" app-profile true

  run check_persistence_browser_extensions

  [[ "$(detail_of persistence.browser-extensions)" == "Chrome (Work): uBlock Origin Lite; Firefox (default-release): Multi-Account Containers" ]]
}

@test "no browser extensions pass" {
  run check_persistence_browser_extensions

  [[ "$(result_of persistence.browser-extensions)" == pass ]]
}

@test "active system extensions are listed with their state" {
  stub_command systemextensionsctl "$(cat "$FIXTURES_DIR/systemextensionsctl-list.txt")"

  run check_persistence_system_extensions

  [[ "$(detail_of persistence.system-extensions)" == "com.example.security.network-extension, com.example.vpn.transparent-proxy (waiting for user)" ]]
}

@test "no system extensions says none found" {
  stub_command systemextensionsctl "0 extension(s)"

  run check_persistence_system_extensions

  [[ "$(detail_of persistence.system-extensions)" == "none found" ]]
}
