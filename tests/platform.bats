#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/10-platform.sh
}

@test "pending software updates warn and name each update" {
  stub_command softwareupdate "$(cat "$FIXTURES_DIR/softwareupdate-pending.txt")"

  run check_platform_updates

  [[ "$(detail_of platform.updates)" == "Safari27.0TahoeAuto-27.0, macOS Tahoe 26.7.1-25G241, macOS 27.0.1-26A434" ]]
}

@test "no pending software update passes" {
  stub_command softwareupdate $'Software Update Tool\n\nFinding available software\nNo new software available.'

  run check_platform_updates

  [[ "$(status_of platform.updates)" == pass ]]
}

@test "unanswered software update query is skipped" {
  stub_command softwareupdate "Can't connect to the Apple Software Update server." 1

  run check_platform_updates

  [[ "$(status_of platform.updates)" == skip ]]
}

@test "security responses on pass" {
  stub_command defaults 1

  run check_platform_security_responses

  [[ "$(status_of platform.security-responses)" == pass ]]
}

@test "security responses off fail" {
  stub_command defaults 0

  run check_platform_security_responses

  [[ "$(status_of platform.security-responses)" == fail ]]
}

@test "unset security response preferences fail" {
  stub_command defaults "The domain/default pair does not exist" 1

  run check_platform_security_responses

  [[ "$(detail_of platform.security-responses)" == "CriticalUpdateInstall=unset, ConfigDataInstall=unset" ]]
}

@test "macOS updates not installed automatically warn" {
  stub_command defaults 0

  run check_platform_auto_install

  [[ "$(status_of platform.auto-install)" == warn ]]
}

@test "FileVault on passes" {
  stub_command fdesetup "FileVault is On."

  run check_platform_filevault

  [[ "$(status_of platform.filevault)" == pass ]]
}

@test "FileVault off fails" {
  stub_command fdesetup "FileVault is Off."

  run check_platform_filevault

  [[ "$(status_of platform.filevault)" == fail ]]
}

@test "FileVault on while still encrypting passes" {
  stub_command fdesetup $'FileVault is On.\nEncryption in progress: Percent completed = 40'

  run check_platform_filevault

  [[ "$(status_of platform.filevault)" == pass ]]
}

@test "unknown FileVault state warns" {
  stub_command fdesetup "Decryption in progress"

  run check_platform_filevault

  [[ "$(status_of platform.filevault)" == warn ]]
}

@test "SIP enabled passes" {
  stub_command csrutil "System Integrity Protection status: enabled."

  run check_platform_sip

  [[ "$(status_of platform.sip)" == pass ]]
}

@test "SIP disabled fails" {
  stub_command csrutil "System Integrity Protection status: disabled."

  run check_platform_sip

  [[ "$(status_of platform.sip)" == fail ]]
}

@test "Gatekeeper enabled passes" {
  stub_command spctl "assessments enabled"

  run check_platform_gatekeeper

  [[ "$(status_of platform.gatekeeper)" == pass ]]
}

@test "Gatekeeper disabled fails" {
  stub_command spctl "assessments disabled"

  run check_platform_gatekeeper

  [[ "$(status_of platform.gatekeeper)" == fail ]]
}

@test "startup security without sudo is skipped" {
  stub_command uname arm64
  stub_no_sudo

  run check_platform_startup_security

  [[ "$(status_of platform.startup-security)" == skip ]]
}

@test "startup security on Intel is skipped" {
  stub_command uname x86_64

  run check_platform_startup_security

  [[ "$(status_of platform.startup-security)" == skip ]]
}

@test "full startup security passes" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Full Security"

  run check_platform_startup_security

  [[ "$(status_of platform.startup-security)" == pass ]]
}

@test "reduced startup security warns" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Reduced Security"

  run check_platform_startup_security

  [[ "$(status_of platform.startup-security)" == warn ]]
}

@test "permissive startup security fails" {
  stub_command uname arm64
  stub_command sudo "Security Mode: Permissive Security"

  run check_platform_startup_security

  [[ "$(status_of platform.startup-security)" == fail ]]
}

@test "recent XProtect definitions pass" {
  stub_command xprotect "Version: 5366 Installed: $(days_ago 2) +0000"

  run check_platform_xprotect

  [[ "$(status_of platform.xprotect)" == pass ]]
}

@test "old XProtect definitions warn" {
  stub_command xprotect "Version: 5000 Installed: $(days_ago 90) +0000"

  run check_platform_xprotect

  [[ "$(status_of platform.xprotect)" == warn ]]
}

@test "MDM enrollment is reported as information" {
  stub_command profiles $'Enrolled via DEP: No\nMDM enrollment: No'

  run check_platform_mdm

  [[ "$(detail_of platform.mdm)" == "Enrolled via DEP: No, MDM enrollment: No" ]]
}
