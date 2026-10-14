# Finds installed software listed in data/inventory.tsv; source it, don't run it.

INVENTORY_CATALOGUE="${INVENTORY_CATALOGUE:-$ROOT_DIR/data/inventory.tsv}"

# Usage: report_catalogue id title category
report_catalogue() {
  local found
  found="$(catalogue_matches "$3" | join_lines)"
  report_pass "$1" "$2" "${found:-none found}"
}

# Prints "name version" for each installed item of a category, each name once.
catalogue_matches() {
  local apps _category name finder
  apps="$(installed_apps)"
  catalogue_rows "$1" | while IFS=$'\t' read -r _category name finder; do
    case "$finder" in
      app:*) echo "$apps" | apps_with_field 1 "${finder#app:}" ;;
      name:*) echo "$apps" | apps_with_field 2 "${finder#name:}" ;;
      cmd:*) ! has_command "${finder#cmd:}" || printf '%s\t\n' "$name" ;;
      path:*) [[ ! -e "$(expand_tilde "${finder#path:}")" ]] || printf '%s\t\n' "$name" ;;
    esac
  done | awk -F'\t' '!seen[$1]++ { print ($2 == "") ? $1 : $1 " " $2 }'
}

# Usage: catalogue_rows category
catalogue_rows() {
  awk -F'\t' -v category="$1" '$1 == category' "$INVENTORY_CATALOGUE"
}

# Usage: apps_with_field 1|2 glob, with installed_apps lines on stdin
# Prints "name<TAB>version" for apps whose bundle id (1) or name (2) matches the glob.
apps_with_field() {
  local bundle_id app_name version field
  while IFS=$'\t' read -r bundle_id app_name version; do
    field="$bundle_id"
    [[ "$1" == 1 ]] || field="$app_name"
    # shellcheck disable=SC2053 # $2 is a glob
    [[ "$field" != $2 ]] || printf '%s\t%s\n' "$app_name" "${version#-}"
  done
}

# Prints "bundle id<TAB>name<TAB>version" for the apps in $INVENTORY_APP_DIRS and their subfolders,
# with "-" for a missing value.
installed_apps() {
  local app plist
  app_paths | while IFS= read -r app; do
    plist="$app/Contents/Info.plist"
    printf '%s\t%s\t%s\n' "$(plist_value CFBundleIdentifier "$plist")" "$(basename "$app" .app)" \
      "$(plist_value CFBundleShortVersionString "$plist")"
  done
}

# Prints the path of each app in $INVENTORY_APP_DIRS and their subfolders, installers left out.
app_paths() {
  # shellcheck disable=SC2086 # one folder per word
  find $INVENTORY_APP_DIRS -maxdepth 2 -name '*.app' -prune ! -iname '*install*' 2>/dev/null | sort
}

# Usage: plist_value key plist
plist_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null || echo -
}

# Prints "name version" for the apps that are neither Apple's nor in the catalogue.
uncatalogued_apps() {
  local bundle_id app_name version
  installed_apps | while IFS=$'\t' read -r bundle_id app_name version; do
    [[ "$bundle_id" != com.apple.* ]] || continue
    ! in_catalogue "$bundle_id" "$app_name" || continue
    version="${version#-}"
    echo "$app_name${version:+ $version}"
  done
}

# Usage: in_catalogue bundle_id app_name
# shellcheck disable=SC2053 # the catalogue holds globs
in_catalogue() {
  local _category _name finder
  while IFS=$'\t' read -r _category _name finder; do
    case "$finder" in
      app:*) [[ "$1" != ${finder#app:} ]] || return 0 ;;
      name:*) [[ "$2" != ${finder#name:} ]] || return 0 ;;
    esac
  done < <(grep -v '^#' "$INVENTORY_CATALOGUE")
  return 1
}
