# Persistence and permissions: what starts on its own, and what apps may access.

SCRIPT_INTERPRETERS="sh bash zsh dash python python3 perl ruby node osascript"
BACKGROUND_ITEM_TYPES="login item|agent|daemon|legacy agent|legacy daemon"
# Chromium browsers: name, then folder under ~/Library/Application Support
CHROMIUM_BROWSERS="Chrome	Google/Chrome
Edge	Microsoft Edge
Brave	BraveSoftware/Brave-Browser
Vivaldi	Vivaldi
Arc	Arc/User Data
Chromium	Chromium"
SAFARI_EXTENSION_POINTS="com.apple.Safari.web-extension com.apple.Safari.extension com.apple.Safari.content-blocker"

run_persistence_checks() {
  run_root_check "launch agents and daemons" check_persistence_launch_items
  run_root_check "login items and background apps" check_persistence_login_items
  run_check "system extensions" check_persistence_system_extensions
  run_check "browsers" check_persistence_browsers
  run_check "browser extensions" check_persistence_browser_extensions
  run_check "privacy permissions" check_persistence_privacy_permissions
  run_check "accessory connections" check_persistence_accessories
}

check_persistence_launch_items() {
  local reviews problems notes
  reviews="$(launch_item_reviews)"
  problems="$(echo "$reviews" | awk -F'\t' '$1 == "problem" { print $2 }' | join_lines)"
  notes="$(echo "$reviews" | awk -F'\t' '$1 == "note" { print $2 }' | join_lines)"
  if [[ -n "$problems" ]]; then
    report_fail persistence.launch-items medium "Launch agents and daemons run signed programs" "$problems" \
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
    codesign --verify -- "$1" >/dev/null 2>&1
  else
    sudo -n codesign --verify -- "$1" >/dev/null 2>&1
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

check_persistence_login_items() {
  if ! has_command sfltool; then
    report_skip persistence.login-items "Login items and background apps" "sfltool command not found"
    return
  fi
  # Without root, sfltool asks for an admin password in a dialog.
  if ! sudo_available; then
    report_skip persistence.login-items "Login items and background apps" "needs sudo: run 'sudo -v' first"
    return
  fi
  local items problems
  items="$(sudo -n sfltool dumpbtm 2>/dev/null | enabled_background_items)"
  problems="$(echo "$items" | background_item_problems | join_lines)"
  if [[ -n "$problems" ]]; then
    report_fail persistence.login-items low "Login items and background apps run known programs" "$problems" \
      "System Settings › General › Login Items & Extensions: turn off leftovers and anything you don't recognise"
  elif [[ -n "$items" ]]; then
    report_pass persistence.login-items "Login items and background apps" \
      "$(echo "$items" | wc -l | tr -d ' ') enabled: $(echo "$items" | count_by_developer)"
  else
    report_pass persistence.login-items "No login items or background apps"
  fi
}

# Prints "name<TAB>developer<TAB>identifier<TAB>team<TAB>program" for each enabled item of
# the system and of this user; "-" stands for a missing value.
enabled_background_items() {
  awk -v user="$(id -u)" -v types="$BACKGROUND_ITEM_TYPES" '
    function value(key) {
      return (field[key] == "" || field[key] == "(null)") ? "-" : field[key]
    }
    function print_item(  type) {
      type = field["Type"]
      sub(/ \(0x[0-9a-f]+\)$/, "", type)
      if (in_item && (uid == -2 || uid == 0 || uid == user) \
          && index("|" types "|", "|" type "|") && field["Disposition"] ~ /^\[enabled/)
        print value("Name") "\t" value("Developer Name") "\t" value("Identifier") "\t" value("Team Identifier") "\t" value("Executable Path")
      split("", field)
      in_item = 0
    }
    /^ Records for UID / { print_item(); uid = $4; next }
    /^ #[0-9]+:$/ { print_item(); in_item = 1; next }
    in_item && match($0, /^ +[A-Za-z ]+: /) {
      key = substr($0, 1, RLENGTH - 2)
      sub(/^ +/, "", key)
      field[key] = substr($0, RLENGTH + 1)
    }
    END { print_item() }'
}

# Prints the items whose program is gone, or that have no Team ID and are not Apple's.
background_item_problems() {
  local name identifier team program
  while IFS=$'\t' read -r name _ identifier team program; do
    if [[ "$program" == /* && ! -e "$program" ]]; then
      echo "$name: program missing ($program)"
    elif [[ "$team" == - && "$identifier" != *.com.apple.* ]]; then
      echo "$name: no Team ID"
    fi
  done
}

# Prints "Developer (count)" for each developer, or the item name when the developer is unknown.
count_by_developer() {
  awk -F'\t' '{ print ($2 == "-") ? $1 : $2 }' | sort | uniq -c \
    | awk '{ count = $1; sub(/^ *[0-9]+ /, ""); print $0 " (" count ")" }' | join_lines
}

check_persistence_privacy_permissions() {
  report_manual persistence.privacy-permissions "Review privacy permissions" \
    "System Settings › Privacy & Security: review Full Disk Access, Accessibility, Input Monitoring, Screen & System Audio Recording, Automation, Developer Tools"
}

check_persistence_accessories() {
  report_manual persistence.accessories "New accessories must ask before connecting" \
    "System Settings › Privacy & Security › Allow accessories to connect: Ask for New Accessories"
}

check_persistence_system_extensions() {
  local extensions
  extensions="$(systemextensionsctl list 2>/dev/null | system_extensions | join_lines)"
  report_pass persistence.system-extensions "System extensions" "${extensions:-none found}"
}

# Prints each system extension's bundle id, with its state unless it is enabled;
# old versions waiting to be removed are left out.
system_extensions() {
  awk -F'\t' 'NF >= 6 && $3 != "teamID" && $6 !~ /terminated/ {
    id = $4; sub(/ \(.*/, "", id)
    state = $6; gsub(/[][]/, "", state); sub(/^activated /, "", state)
    print id (state == "enabled" ? "" : " (" state ")")
  }' | sort -u
}

check_persistence_browsers() {
  report_catalogue persistence.browsers "Browsers" browsers
}

check_persistence_browser_extensions() {
  local extensions unpacked
  extensions="$(browser_extensions)"
  unpacked="$(echo "$extensions" | awk -F'\t' '$3 == "unpacked" { print $1 ": " $2 }' | join_lines)"
  if [[ -n "$unpacked" ]]; then
    report_fail persistence.browser-extensions medium "Browser extensions come from a store" \
      "loaded from a folder, never updated: $unpacked" \
      "Remove them unless you are developing them; review the others at chrome://extensions"
  elif [[ -n "$extensions" ]]; then
    report_pass persistence.browser-extensions "Browser extensions to review" \
      "$(echo "$extensions" | extensions_by_browser)"
  else
    report_pass persistence.browser-extensions "No browser extensions installed"
  fi
}

# Prints "browser<TAB>extension<TAB>on|off|unpacked" for the extensions you installed.
browser_extensions() {
  chromium_extensions
  firefox_extensions
  safari_extensions
}

chromium_extensions() {
  local browser folder profile_dir
  echo "$CHROMIUM_BROWSERS" | while IFS=$'\t' read -r browser folder; do
    folder="$HOME/Library/Application Support/$folder"
    for profile_dir in "$folder"/*/; do
      [[ -e "$profile_dir/Preferences" ]] || continue
      chromium_profile_extensions "$browser ($(chromium_profile_name "$folder" "$profile_dir"))" "$profile_dir"
    done
  done
}

# Usage: chromium_profile_name browser_folder profile_dir
chromium_profile_name() {
  local dir_name
  dir_name="$(basename "$2")"
  jq -r --arg dir "$dir_name" '.profile.info_cache[$dir].name // $dir' "$1/Local State" 2>/dev/null || echo "$dir_name"
}

# Usage: chromium_profile_extensions label profile_dir
# Locations 5 and 10 ship with the browser; 4 is a folder loaded in developer mode.
chromium_profile_extensions() {
  cat "$2/Preferences" "$2/Secure Preferences" 2>/dev/null | jq -rs --arg browser "$1" '
    reduce .[].extensions.settings as $settings ({}; . * ($settings // {}))
    | to_entries[] | .value
    | select((.location | IN(5, 10) | not) and .was_installed_by_default != true)
    | [$browser, (.manifest.name // "unnamed"),
        (if .location == 4 then "unpacked"
         elif (.disable_reasons // [] | if type == "array" then length > 0 else . != 0 end) then "off"
         else "on" end)]
    | @tsv' 2>/dev/null | sort -t $'\t' -k2
}

firefox_extensions() {
  local extensions_file profile
  for extensions_file in "$HOME/Library/Application Support/Firefox/Profiles"/*/extensions.json; do
    [[ -e "$extensions_file" ]] || continue
    profile="$(basename "$(dirname "$extensions_file")")"
    jq -r --arg browser "Firefox (${profile#*.})" '
      .addons[]? | select(.type == "extension" and .location == "app-profile")
      | [$browser, (.defaultLocale.name // .id), (if .active then "on" else "off" end)]
      | @tsv' "$extensions_file" 2>/dev/null | sort -t $'\t' -k2
  done
}

# Safari extensions ship inside apps, so each is named after its app.
safari_extensions() {
  local point
  has_command pluginkit || return 0
  for point in $SAFARI_EXTENSION_POINTS; do
    pluginkit -mAv -p "$point" 2>/dev/null
  done | awk -F'\t' 'NF >= 4 { print $4 }' \
    | sed -n 's#.*/\([^/]*\)\.app/Contents/PlugIns/.*#\1#p' | sort -u \
    | awk '{ print "Safari\t" $0 "\ton" }'
}

# Prints "Browser: name, name (off); Browser: …" from browser_extensions lines.
extensions_by_browser() {
  awk -F'\t' '
    !($1 in names) { order[++count] = $1 }
    { name = $2 ($3 == "off" ? " (off)" : ""); names[$1] = ($1 in names) ? names[$1] ", " name : name }
    END { for (i = 1; i <= count; i++) printf "%s%s: %s", (i > 1 ? "; " : ""), order[i], names[order[i]] }'
}
