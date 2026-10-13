# Persistence and permissions: what starts on its own, and what apps may access.

SCRIPT_INTERPRETERS="sh bash zsh dash python python3 perl ruby node osascript"

run_persistence_checks() {
  check_persistence_launch_items
  check_persistence_manual_reviews
}

check_persistence_launch_items() {
  local reviews problems notes
  reviews="$(launch_item_reviews)"
  problems="$(echo "$reviews" | awk -F'\t' '$1 == "problem" { print $2 }' | join_lines)"
  notes="$(echo "$reviews" | awk -F'\t' '$1 == "note" { print $2 }' | join_lines)"
  if [[ -n "$problems" ]]; then
    report_warn persistence.launch-items "Launch agents and daemons run signed programs" "$problems" \
      "Remove leftovers of uninstalled apps; investigate anything you don't recognise (KnockKnock helps)"
  else
    report_pass persistence.launch-items "Launch agents and daemons run signed programs" \
      "$(launch_item_plists | wc -l | tr -d ' ') item(s)${notes:+; $notes}"
  fi
}

# Prints "problem<TAB>text" for missing, unsigned or script programs, and "note<TAB>text"
# for items that could not be checked.
launch_item_reviews() {
  local plist label program
  launch_item_plists | while IFS= read -r plist; do
    label="$(basename "$plist" .plist)"
    program="$(launch_item_program "$plist")"
    if [[ -z "$program" ]]; then
      printf 'note\t%s: no program set\n' "$label"
    elif [[ ! -e "$program" ]]; then
      printf 'problem\t%s: program missing (%s)\n' "$label" "$program"
    elif [[ " $SCRIPT_INTERPRETERS " == *" $(basename "$program") "* ]]; then
      printf 'problem\t%s: runs a script through %s\n' "$label" "$(basename "$program")"
    elif [[ ! -r "$program" ]] && ! sudo_available; then
      printf 'note\t%s: signature not checked (needs sudo)\n' "$label"
    elif ! verify_signature "$program"; then
      printf 'problem\t%s: unsigned or tampered program (%s)\n' "$label" "$program"
    fi
  done
}

verify_signature() {
  if [[ -r "$1" ]]; then
    codesign --verify "$1" >/dev/null 2>&1
  else
    sudo -n codesign --verify "$1" >/dev/null 2>&1
  fi
}

# Prints the third-party launchd plists of this user and of the system.
launch_item_plists() {
  local dir
  # shellcheck disable=SC2086 # SYSTEM_LAUNCH_DIRS is a space-separated list
  for dir in "$HOME/Library/LaunchAgents" $SYSTEM_LAUNCH_DIRS; do
    find "$dir" -maxdepth 1 -name '*.plist' ! -name 'com.apple.*' 2>/dev/null
  done | sort
}

launch_item_program() {
  plutil -extract Program raw -o - "$1" 2>/dev/null \
    || plutil -extract ProgramArguments.0 raw -o - "$1" 2>/dev/null \
    || true
}

check_persistence_manual_reviews() {
  report_manual persistence.login-items "Review login items and background apps" \
    "System Settings › General › Login Items & Extensions: remove what you don't need"
  report_manual persistence.privacy-permissions "Review privacy permissions" \
    "System Settings › Privacy & Security: review Full Disk Access, Accessibility, Input Monitoring, Screen & System Audio Recording, Automation, Developer Tools"
  report_manual persistence.accessories "New accessories must ask before connecting" \
    "System Settings › Privacy & Security › Allow accessories to connect: Ask for New Accessories"
  report_manual persistence.browser-extensions "Review browser extensions" \
    "Remove unused extensions; use a separate browser profile for cloud and admin consoles"
}
