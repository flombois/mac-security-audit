#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/10-platform.sh
}

# Usage: given_update_scan days_ago [updates_json]; macOS's last update check, as its preferences hold it.
given_update_scan() {
  SOFTWARE_UPDATE_PREFS="$BATS_TEST_TMPDIR/com.apple.SoftwareUpdate"
  plutil -create xml1 "$SOFTWARE_UPDATE_PREFS.plist"
  plutil -insert LastSuccessfulDate -date "$(date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ)" "$SOFTWARE_UPDATE_PREFS.plist"
  plutil -insert RecommendedUpdates -json "${2:-[]}" "$SOFTWARE_UPDATE_PREFS.plist"
}

@test "pending updates are read from macOS's last check" {
  given_update_scan 1 '[{"Display Name": "Safari", "Display Version": "27.0"}, {"Display Name": "macOS Tahoe 26.7.1", "Display Version": "26.7.1"}]'

  run check_platform_updates

  [[ "$(detail_of platform.updates)" == "Safari 27.0, macOS Tahoe 26.7.1 (macOS checked $(date -u -v-1d +%F))" ]]
}

@test "a recent check without updates passes" {
  given_update_scan 1

  run check_platform_updates

  [[ "$(result_of platform.updates)" == pass ]]
}

@test "an old check without updates is skipped" {
  given_update_scan 30

  run check_platform_updates

  [[ "$(result_of platform.updates)" == skipped && "$(detail_of platform.updates)" == *"30 days ago; run with --check-updates" ]]
}

@test "an old check with updates still warns" {
  given_update_scan 30 '[{"Display Name": "Safari", "Display Version": "27.0"}]'

  run check_platform_updates

  [[ "$(result_of platform.updates)" == "fail medium" ]]
}

@test "no check by macOS yet is skipped" {
  SOFTWARE_UPDATE_PREFS="$BATS_TEST_TMPDIR/missing"

  run check_platform_updates

  [[ "$(result_of platform.updates)" == skipped ]]
}

@test "Apple's servers are only asked with --check-updates" {
  given_update_scan 1
  stub_script softwareupdate <<STUB
touch "$BATS_TEST_TMPDIR/asked-apple"
STUB

  run check_platform_updates

  [[ ! -e "$BATS_TEST_TMPDIR/asked-apple" ]]
}

@test "--check-updates: pending software updates warn and name each update" {
  CHECK_UPDATES=true
  stub_command softwareupdate "$(cat "$FIXTURES_DIR/softwareupdate-pending.txt")"

  run check_platform_updates

  [[ "$(detail_of platform.updates)" == "Safari27.0TahoeAuto-27.0, macOS Tahoe 26.7.1-25G241, macOS 27.0.1-26A434" ]]
}

@test "--check-updates: no pending software update passes" {
  CHECK_UPDATES=true
  stub_command softwareupdate $'Software Update Tool\n\nFinding available software\nNo new software available.'

  run check_platform_updates

  [[ "$(result_of platform.updates)" == pass ]]
}

@test "--check-updates: unanswered software update query is an error" {
  CHECK_UPDATES=true
  stub_command softwareupdate "Can't connect to the Apple Software Update server." 1

  run check_platform_updates

  [[ "$(result_of platform.updates)" == error ]]
}

@test "security responses on pass" {
  stub_command defaults 1

  run check_platform_security_responses

  [[ "$(result_of platform.security-responses)" == pass ]]
}

@test "security responses off fail" {
  stub_command defaults 0

  run check_platform_security_responses

  [[ "$(result_of platform.security-responses)" == "fail high" ]]
}

@test "unset security response preferences fail" {
  stub_command defaults "The domain/default pair does not exist" 1

  run check_platform_security_responses

  [[ "$(detail_of platform.security-responses)" == "CriticalUpdateInstall=unset, ConfigDataInstall=unset" ]]
}

@test "macOS updates not installed automatically warn" {
  stub_command defaults 0

  run check_platform_auto_install

  [[ "$(result_of platform.auto-install)" == "fail medium" ]]
}

@test "FileVault on passes" {
  stub_command fdesetup "FileVault is On."

  run check_platform_filevault

  [[ "$(result_of platform.filevault)" == pass ]]
}

@test "FileVault off fails" {
  stub_command fdesetup "FileVault is Off."

  run check_platform_filevault

  [[ "$(result_of platform.filevault)" == "fail high" ]]
}

@test "FileVault on while still encrypting passes" {
  stub_command fdesetup $'FileVault is On.\nEncryption in progress: Percent completed = 40'

  run check_platform_filevault

  [[ "$(result_of platform.filevault)" == pass ]]
}

@test "unknown FileVault state warns" {
  stub_command fdesetup "Decryption in progress"

  run check_platform_filevault

  [[ "$(result_of platform.filevault)" == "fail medium" ]]
}

@test "SIP enabled passes" {
  stub_command csrutil "System Integrity Protection status: enabled."

  run check_platform_sip

  [[ "$(result_of platform.sip)" == pass ]]
}

@test "SIP disabled fails" {
  stub_command csrutil "System Integrity Protection status: disabled."

  run check_platform_sip

  [[ "$(result_of platform.sip)" == "fail high" ]]
}

@test "Gatekeeper enabled passes" {
  stub_command spctl "assessments enabled"

  run check_platform_gatekeeper

  [[ "$(result_of platform.gatekeeper)" == pass ]]
}

@test "Gatekeeper disabled fails" {
  stub_command spctl "assessments disabled"

  run check_platform_gatekeeper

  [[ "$(result_of platform.gatekeeper)" == "fail high" ]]
}

@test "startup security without sudo is skipped" {
  stub_command uname arm64
  stub_no_sudo

  run check_platform_startup_security

  [[ "$(result_of platform.startup-security)" == skipped ]]
}

@test "startup security on Intel is skipped" {
  stub_command uname x86_64

  run check_platform_startup_security

  [[ "$(result_of platform.startup-security)" == skipped ]]
}

@test "full startup security passes" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Full Security"

  run check_platform_startup_security

  [[ "$(result_of platform.startup-security)" == pass ]]
}

@test "reduced startup security warns" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Reduced Security"

  run check_platform_startup_security

  [[ "$(result_of platform.startup-security)" == "fail medium" ]]
}

@test "permissive startup security fails" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Permissive Security"

  run check_platform_startup_security

  [[ "$(result_of platform.startup-security)" == "fail high" ]]
}

@test "recent XProtect definitions pass" {
  stub_command xprotect "Version: 5366 Installed: $(days_ago 2) +0000"

  run check_platform_xprotect

  [[ "$(result_of platform.xprotect)" == pass ]]
}

@test "old XProtect definitions warn" {
  stub_command xprotect "Version: 5000 Installed: $(days_ago 90) +0000"

  run check_platform_xprotect

  [[ "$(result_of platform.xprotect)" == "fail medium" ]]
}

@test "MDM enrollment is reported as information" {
  stub_command profiles $'Enrolled via DEP: No\nMDM enrollment: No'

  run check_platform_mdm

  [[ "$(detail_of platform.mdm)" == "Enrolled via DEP: No, MDM enrollment: No" ]]
}

@test "without sudo only your own profiles are listed" {
  stub_no_sudo
  stub_command profiles "someone[1] attribute: profileIdentifier: com.example.wifi"

  run check_platform_profiles

  [[ "$(detail_of platform.profiles)" == "com.example.wifi (device profiles need sudo: run 'sudo -v' first)" ]]
}

@test "with cached sudo every profile is listed" {
  given_cached_sudo
  stub_script profiles <<'EOF'
[[ "$*" == "list -all" ]] && echo "_computerlevel[1] attribute: profileIdentifier: com.example.mdm"
EOF

  run check_platform_profiles

  [[ "$(detail_of platform.profiles)" == "com.example.mdm" ]]
}

@test "unsigned app warns" {
  given_app "Homemade Tool" com.example.homemade 1.0

  run check_platform_app_signatures

  [[ "$(detail_of platform.app-signatures)" == "Homemade Tool (not signed)" ]]
}

@test "ad-hoc signed app warns" {
  given_app "Quick Build" com.example.quick 1.0
  stub_command codesign $'Executable=/Applications/Quick Build.app/Contents/MacOS/Quick Build\nSignature=adhoc'

  run check_platform_app_signatures

  [[ "$(detail_of platform.app-signatures)" == "Quick Build (ad-hoc signed)" ]]
}

@test "Apple apps are not assessed" {
  given_app Safari com.apple.Safari 26.6

  run check_platform_app_signatures

  [[ "$(result_of platform.app-signatures)" == pass ]]
}

# Usage: given_gatekeeper_output assessment_output
given_gatekeeper_output() {
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/spctl.out"
  stub_script spctl <<EOF
[[ "\$1" == --status ]] && { echo "assessments enabled"; exit 0; }
cat "$BATS_TEST_TMPDIR/spctl.out" >&2
exit 3
EOF
}

@test "full check names Gatekeeper's reason" {
  VERIFY_APPS=true
  given_app "Example" com.example.app 1.0
  given_gatekeeper_output $'/Applications/Example.app: rejected\nsource=Unnotarized Developer ID'

  run check_platform_app_signatures

  [[ "$(detail_of platform.app-signatures)" == "Example (Unnotarized Developer ID)" ]]
}

@test "full check falls back to Gatekeeper's message" {
  VERIFY_APPS=true
  given_app "Example" com.example.app 1.0
  given_gatekeeper_output "/Applications/Example.app: a sealed resource is missing or invalid"

  run check_platform_app_signatures

  [[ "$(detail_of platform.app-signatures)" == "Example (a sealed resource is missing or invalid)" ]]
}

@test "full check is skipped when Gatekeeper is off" {
  VERIFY_APPS=true
  stub_command spctl "assessments disabled"

  run check_platform_app_signatures

  [[ "$(result_of platform.app-signatures)" == skipped ]]
}
