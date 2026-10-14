# Platform: OS updates and built-in protections.

SOFTWARE_UPDATE_PREFS="${SOFTWARE_UPDATE_PREFS:-/Library/Preferences/com.apple.SoftwareUpdate}"
# Older than this, macOS's own update check no longer counts as up to date.
UPDATE_CHECK_MAX_AGE_DAYS=7
XPROTECT_MAX_AGE_DAYS=30
VERIFY_APPS="${VERIFY_APPS:-false}"
CHECK_UPDATES="${CHECK_UPDATES:-false}"

run_platform_checks() {
  run_check "pending software updates" check_platform_updates
  run_check "automatic security responses" check_platform_security_responses
  run_check "automatic macOS updates" check_platform_auto_install
  run_check "FileVault" check_platform_filevault
  run_check "System Integrity Protection" check_platform_sip
  run_check "Gatekeeper" check_platform_gatekeeper
  run_root_check "startup security" check_platform_startup_security
  run_check "XProtect definitions" check_platform_xprotect
  run_check "device management enrollment" check_platform_mdm
  run_root_check "configuration profiles" check_platform_profiles
  run_check "security software" check_platform_security_software
  run_check "app signatures" check_platform_app_signatures
  run_check "other apps" check_platform_other_apps
}

# Reads the result of macOS's own background update check; --check-updates asks Apple's servers,
# which takes about 10 s.
check_platform_updates() {
  if [[ "$CHECK_UPDATES" == true ]]; then
    check_updates_online
  else
    check_updates_from_last_scan
  fi
}

check_updates_online() {
  local output labels
  output="$(softwareupdate -l 2>&1)" || true
  labels="$(echo "$output" | sed -n 's/^\* Label: //p')"
  if [[ -n "$labels" ]]; then
    report_fail platform.updates medium "Software updates pending" \
      "$(echo "$labels" | join_lines)" \
      "Install with System Settings › General › Software Update, or: softwareupdate -i -a"
  elif [[ "$output" == *"No new software available"* ]]; then
    report_pass platform.updates "Software up to date"
  else
    report_error platform.updates "Software updates" "softwareupdate gave no answer (offline?)"
  fi
}

check_updates_from_last_scan() {
  local prefs="$SOFTWARE_UPDATE_PREFS.plist" checked age updates
  checked="$(plutil -extract LastSuccessfulDate raw -o - "$prefs" 2>/dev/null)"
  if [[ -z "$checked" ]]; then
    report_skip platform.updates "Software updates" "macOS has not checked for updates yet; run with --check-updates"
    return
  fi
  age="$(days_since "$(echo "$checked" | sed -E 's/T/ /; s/Z$//')")"
  checked="macOS checked ${checked%%T*}"
  updates="$(plutil -extract RecommendedUpdates json -o - "$prefs" 2>/dev/null |
    jq -r '.[] | ."Display Name" as $name | (."Display Version" // "") as $version
      | if $name | endswith($version) then $name else "\($name) \($version)" end' 2>/dev/null |
    join_lines)"
  if [[ -n "$updates" ]]; then
    report_fail platform.updates medium "Software updates pending" "$updates ($checked)" \
      "Install with System Settings › General › Software Update, or: softwareupdate -i -a"
  elif [[ "${age:-0}" -le "$UPDATE_CHECK_MAX_AGE_DAYS" ]]; then
    report_pass platform.updates "Software up to date" "$checked"
  else
    report_skip platform.updates "Software updates" "$checked $age days ago; run with --check-updates"
  fi
}

check_platform_security_responses() {
  local critical config
  critical="$(read_software_update_pref CriticalUpdateInstall)"
  config="$(read_software_update_pref ConfigDataInstall)"
  if [[ "$critical" == 1 && "$config" == 1 ]]; then
    report_pass platform.security-responses "Security responses and system data files install automatically"
  else
    report_fail platform.security-responses high "Security responses and system data files install automatically" \
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
    report_fail platform.auto-install medium "macOS updates install automatically" \
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
      report_fail platform.filevault high "FileVault disk encryption on" "$output" \
        "System Settings › Privacy & Security › FileVault: turn on, keep the recovery key off this Mac" ;;
    *)
      report_fail platform.filevault medium "FileVault disk encryption on" "$output" \
        "Wait for encryption to finish, then run the audit again" ;;
  esac
}

check_platform_sip() {
  local output
  output="$(csrutil status 2>&1)" || true
  if [[ "$output" == *"status: enabled."* ]]; then
    report_pass platform.sip "System Integrity Protection on"
  else
    report_fail platform.sip high "System Integrity Protection on" "$output" \
      "Boot into recoveryOS and run: csrutil enable"
  fi
}

check_platform_gatekeeper() {
  local output
  output="$(spctl --status 2>&1)" || true
  if [[ "$output" == "assessments enabled" ]]; then
    report_pass platform.gatekeeper "Gatekeeper on"
  else
    report_fail platform.gatekeeper high "Gatekeeper on" "$output" \
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
      report_fail platform.startup-security high "Startup security at Full Security" "Permissive Security" \
        "recoveryOS › Utilities › Startup Security Utility: choose Full Security" ;;
    *[Rr]educed*)
      report_fail platform.startup-security medium "Startup security at Full Security" "Reduced Security" \
        "recoveryOS › Utilities › Startup Security Utility: choose Full Security unless you need kernel extensions" ;;
    *[Ff]ull*)
      report_pass platform.startup-security "Startup security at Full Security" ;;
    *)
      report_error platform.startup-security "Startup security at Full Security" "could not read the bputil output" ;;
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
    report_pass platform.xprotect "XProtect definitions" "$output"
  elif [[ "$age" -gt "$XPROTECT_MAX_AGE_DAYS" ]]; then
    report_fail platform.xprotect medium "XProtect definitions recent" "$output ($age days old)" \
      "Turn on automatic security responses, or run: sudo xprotect update"
  else
    report_pass platform.xprotect "XProtect definitions recent" "$output"
  fi
}

check_platform_mdm() {
  local output
  output="$(profiles status -type enrollment 2>&1)" || true
  report_pass platform.mdm "Device management enrollment" "$(echo "$output" | join_lines)"
}

check_platform_security_software() {
  report_catalogue platform.security-software "Security software" security-software
}

check_platform_other_apps() {
  local apps
  apps="$(uncatalogued_apps | join_lines)"
  report_pass platform.other-apps "Other apps" "${apps:-none found}"
}

# Device-wide profiles need root; without it, only your own are listed.
check_platform_profiles() {
  local profiles note=""
  if sudo_available; then
    profiles="$(sudo -n profiles list -all 2>/dev/null | profile_ids)"
  else
    profiles="$(profiles list 2>/dev/null | profile_ids)"
    note=" (device profiles need sudo: run 'sudo -v' first)"
  fi
  report_pass platform.profiles "Configuration profiles" "${profiles:-none found}$note"
}

profile_ids() {
  sed -n 's/.*attribute: profileIdentifier: //p' | sort -u | join_lines
}

# Reads signatures only; --verify-apps runs Gatekeeper's full check, which hashes every file.
check_platform_app_signatures() {
  if [[ "$VERIFY_APPS" == true ]]; then
    check_apps_with_gatekeeper
  else
    check_app_signatures_only
  fi
}

check_app_signatures_only() {
  local apps total count=0 unsigned
  apps="$(third_party_apps)"
  total="$(echo "$apps" | grep -c .)"
  unsigned="$(echo "$apps" | while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    count=$((count + 1))
    progress_note "$count/$total $(basename "$app" .app)"
    signature_problem "$app"
  done | join_lines)"
  if [[ -n "$unsigned" ]]; then
    report_fail platform.app-signatures low "Apps signed by a developer" "$unsigned" \
      "Reinstall them from the developer's site or the App Store; remove the ones you don't trust"
  else
    report_pass platform.app-signatures "Apps signed by a developer" \
      "signatures only; --verify-apps also runs Gatekeeper's full check"
  fi
}

# Usage: signature_problem app; prints "App (reason)" for unsigned and ad-hoc signed apps.
signature_problem() {
  local signature name
  name="$(basename "$1" .app)"
  if ! signature="$(codesign -dv "$1" 2>&1)"; then
    echo "$name (not signed)"
  elif [[ "$signature" == *"Signature=adhoc"* ]]; then
    echo "$name (ad-hoc signed)"
  fi
}

check_apps_with_gatekeeper() {
  local rejected
  if spctl --status 2>/dev/null | grep -q disabled; then
    report_skip platform.app-signatures "Apps pass Gatekeeper" "Gatekeeper is off, so apps are not assessed"
    return
  fi
  # shellcheck disable=SC2016 # $1 belongs to the child bash
  rejected="$(third_party_apps | tr '\n' '\0' |
    xargs -0 -n 1 -P 4 bash -c "$(declare -f progress_note gatekeeper_rejection); "'gatekeeper_rejection "$1"' _ |
    sort | join_lines)"
  if [[ -n "$rejected" ]]; then
    report_fail platform.app-signatures medium "Apps pass Gatekeeper" "$rejected" \
      "Reinstall them from the developer's site or the App Store; remove the ones you don't trust"
  else
    report_pass platform.app-signatures "Apps pass Gatekeeper"
  fi
}

# Usage: gatekeeper_rejection app; prints "App (reason)" when Gatekeeper rejects it.
gatekeeper_rejection() {
  local assessment reason
  progress_note "Gatekeeper: $(basename "$1" .app)"
  assessment="$(spctl --assess --type execute -vv "$1" 2>&1)" && return
  reason="$(echo "$assessment" | sed -n 's/^source=//p')"
  [[ -n "$reason" ]] || reason="$(echo "$assessment" | head -1 | sed 's/^.*\.app: //')"
  echo "$(basename "$1" .app) (${reason:-rejected})"
}

# Prints the path of each app whose bundle id isn't Apple's.
third_party_apps() {
  local app
  app_paths | while IFS= read -r app; do
    [[ "$(plist_value CFBundleIdentifier "$app/Contents/Info.plist")" == com.apple.* ]] || echo "$app"
  done
}
