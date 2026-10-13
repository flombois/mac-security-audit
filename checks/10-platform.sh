# Platform: OS updates and built-in protections.

SOFTWARE_UPDATE_PREFS=/Library/Preferences/com.apple.SoftwareUpdate
XPROTECT_MAX_AGE_DAYS=30

run_platform_checks() {
  check_platform_updates
  check_platform_security_responses
  check_platform_auto_install
  check_platform_filevault
  check_platform_sip
  check_platform_gatekeeper
  check_platform_startup_security
  check_platform_xprotect
  check_platform_mdm
}

check_platform_updates() {
  local output labels
  output="$(softwareupdate -l 2>&1)" || true
  labels="$(echo "$output" | sed -n 's/^\* Label: //p')"
  if [[ -n "$labels" ]]; then
    report_warn platform.updates "Software updates pending" \
      "$(echo "$labels" | join_lines)" \
      "Install with System Settings › General › Software Update, or: softwareupdate -i -a"
  elif [[ "$output" == *"No new software available"* ]]; then
    report_pass platform.updates "Software up to date"
  else
    report_skip platform.updates "Software updates" "softwareupdate gave no answer (offline?)"
  fi
}

check_platform_security_responses() {
  local critical config
  critical="$(read_software_update_pref CriticalUpdateInstall)"
  config="$(read_software_update_pref ConfigDataInstall)"
  if [[ "$critical" == 1 && "$config" == 1 ]]; then
    report_pass platform.security-responses "Security responses and system data files install automatically"
  else
    report_fail platform.security-responses "Security responses and system data files install automatically" \
      "CriticalUpdateInstall=$critical, ConfigDataInstall=$config" \
      "System Settings › General › Software Update › Automatic Updates: turn on 'Install Security Responses and system files'"
  fi
}

check_platform_auto_install() {
  local auto_install
  auto_install="$(read_software_update_pref AutomaticallyInstallMacOSUpdates)"
  if [[ "$auto_install" == 1 ]]; then
    report_pass platform.auto-install "macOS updates install automatically"
  else
    report_warn platform.auto-install "macOS updates install automatically" \
      "AutomaticallyInstallMacOSUpdates=$auto_install" \
      "System Settings › General › Software Update › Automatic Updates: turn on 'Install macOS updates'"
  fi
}

# Prints the preference value, or "unset".
read_software_update_pref() {
  defaults read "$SOFTWARE_UPDATE_PREFS" "$1" 2>/dev/null || echo unset
}

check_platform_filevault() {
  local output
  output="$(fdesetup status 2>&1)" || true
  case "$output" in
    *"FileVault is On."*)
      report_pass platform.filevault "FileVault disk encryption on" ;;
    *"FileVault is Off."*)
      report_fail platform.filevault "FileVault disk encryption on" "$output" \
        "System Settings › Privacy & Security › FileVault: turn on, keep the recovery key off this Mac" ;;
    *)
      report_warn platform.filevault "FileVault disk encryption on" "$output" \
        "Wait for encryption to finish, then run the audit again" ;;
  esac
}

check_platform_sip() {
  local output
  output="$(csrutil status 2>&1)" || true
  if [[ "$output" == *"status: enabled."* ]]; then
    report_pass platform.sip "System Integrity Protection on"
  else
    report_fail platform.sip "System Integrity Protection on" "$output" \
      "Boot into recoveryOS and run: csrutil enable"
  fi
}

check_platform_gatekeeper() {
  local output
  output="$(spctl --status 2>&1)" || true
  if [[ "$output" == "assessments enabled" ]]; then
    report_pass platform.gatekeeper "Gatekeeper on"
  else
    report_fail platform.gatekeeper "Gatekeeper on" "$output" \
      "Run: sudo spctl --global-enable"
  fi
}

check_platform_startup_security() {
  if [[ "$(uname -m)" != arm64 ]]; then
    report_skip platform.startup-security "Startup security" "Apple silicon only"
    return
  fi
  if ! sudo_available; then
    report_skip platform.startup-security "Startup security" "needs sudo: run 'sudo -v' first"
    return
  fi
  local output
  output="$(sudo -n bputil -d 2>&1)" || true
  case "$output" in
    *[Pp]ermissive*)
      report_fail platform.startup-security "Startup security at Full Security" "Permissive Security" \
        "recoveryOS › Utilities › Startup Security Utility: choose Full Security" ;;
    *[Rr]educed*)
      report_warn platform.startup-security "Startup security at Full Security" "Reduced Security" \
        "recoveryOS › Utilities › Startup Security Utility: choose Full Security unless you need kernel extensions" ;;
    *[Ff]ull*)
      report_pass platform.startup-security "Startup security at Full Security" ;;
    *)
      report_warn platform.startup-security "Startup security at Full Security" "could not read the bputil output" \
        "Check recoveryOS › Utilities › Startup Security Utility" ;;
  esac
}

check_platform_xprotect() {
  if ! has_command xprotect; then
    report_skip platform.xprotect "XProtect definitions" "xprotect command not found"
    return
  fi
  local output installed age
  output="$(xprotect version 2>&1)" || true
  installed="$(echo "$output" | sed -n -E 's/.*Installed: ([0-9-]+ [0-9:]+).*/\1/p')"
  age="$(days_since "$installed")" || age=""
  if [[ -z "$age" ]]; then
    report_info platform.xprotect "XProtect definitions" "$output"
  elif [[ "$age" -gt "$XPROTECT_MAX_AGE_DAYS" ]]; then
    report_warn platform.xprotect "XProtect definitions recent" "$output ($age days old)" \
      "Turn on automatic security responses, or run: sudo xprotect update"
  else
    report_pass platform.xprotect "XProtect definitions recent" "$output"
  fi
}

check_platform_mdm() {
  local output
  output="$(profiles status -type enrollment 2>&1)" || true
  report_info platform.mdm "Device management enrollment" "$(echo "$output" | join_lines)"
}
