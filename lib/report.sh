# Records check results, prints them, and writes the JSON report; source it, don't run it.

STATUSES="pass warn fail info skip manual"
RESULTS_FILE=""
USE_COLOR=false

# Starts an empty result set; $1 is "true" to colour the terminal output.
report_init() {
  RESULTS_FILE="$(mktemp -t mac-security-audit)"
  USE_COLOR="$1"
}

report_cleanup() {
  rm -f "$RESULTS_FILE"
}

report_section() {
  echo
  paint bold "== $1"
}

# Usage: report_pass id title [detail]
report_pass() {
  record_result "$1" pass "$2" "${3:-}" ""
}

# Usage: report_warn id title detail remediation
report_warn() {
  record_result "$1" warn "$2" "$3" "$4"
}

# Usage: report_fail id title detail remediation
report_fail() {
  record_result "$1" fail "$2" "$3" "$4"
}

# Usage: report_info id title detail
report_info() {
  record_result "$1" info "$2" "$3" ""
}

# Usage: report_skip id title reason
report_skip() {
  record_result "$1" skip "$2" "$3" ""
}

# Usage: report_manual id title instructions
report_manual() {
  record_result "$1" manual "$2" "" "$3"
}

# The section is the id prefix: "platform.filevault" belongs to "platform".
record_result() {
  local id="$1" status="$2" title="$3" detail="$4" remediation="$5"
  jq -cn \
    --arg id "$id" --arg section "${id%%.*}" --arg status "$status" \
    --arg title "$title" --arg detail "$detail" --arg remediation "$remediation" \
    '{id: $id, section: $section, status: $status, title: $title, detail: $detail, remediation: $remediation}' \
    >>"$RESULTS_FILE"
  print_result "$status" "$title" "$detail" "$remediation"
}

print_result() {
  local status="$1" title="$2" detail="$3" remediation="$4"
  printf '  %s  %s\n' "$(status_label "$status")" "$title"
  [[ -z "$detail" ]] || printf '          %s\n' "$detail"
  [[ -z "$remediation" ]] || printf '          %s %s\n' "$(paint dim "→")" "$remediation"
}

status_label() {
  case "$1" in
    pass) paint green "PASS  " ;;
    warn) paint yellow "WARN  " ;;
    fail) paint red "FAIL  " ;;
    info) paint blue "INFO  " ;;
    skip) paint dim "SKIP  " ;;
    manual) paint magenta "MANUAL" ;;
  esac
}

# Usage: paint colour text
paint() {
  if [[ "$USE_COLOR" != true ]]; then
    echo "$2"
    return
  fi
  local code
  case "$1" in
    bold) code=1 ;;
    dim) code=2 ;;
    red) code=31 ;;
    green) code=32 ;;
    yellow) code=33 ;;
    blue) code=34 ;;
    magenta) code=35 ;;
  esac
  printf '\033[%sm%s\033[0m\n' "$code" "$2"
}

count_status() {
  jq -s --arg status "$1" '[.[] | select(.status == $status)] | length' "$RESULTS_FILE"
}

print_summary() {
  local status line=""
  for status in $STATUSES; do
    line="$line  $(status_label "$status") $(count_status "$status")"
  done
  echo
  paint bold "== Summary"
  echo "$line"
}

has_failures() {
  [[ "$(count_status fail)" -gt 0 ]]
}

# Writes the pretty-printed JSON report to $1.
write_json_report() {
  jq -n \
    --slurpfile checks "$RESULTS_FILE" \
    --arg host "$(scutil --get LocalHostName 2>/dev/null || hostname)" \
    --arg version "$(sw_vers -productVersion)" \
    --arg build "$(sw_vers -buildVersion)" \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg statuses "$STATUSES" \
    '{
      host: $host,
      macos: {version: $version, build: $build},
      generatedAt: $generatedAt,
      summary: (reduce ($statuses | split(" "))[] as $status ({}; .[$status] = 0)
        | reduce $checks[] as $check (.; .[$check.status] += 1)),
      checks: $checks
    }' >"$1"
}
