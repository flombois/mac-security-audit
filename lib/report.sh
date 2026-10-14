# Records check results, prints the end-of-run report, and writes the JSON report; source it, don't run it.

RESULTS_FILE=""
USE_COLOR=false
REPORT_FRAMED=false

# Usage: report_init color [framed]; each is "true" or "false". Starts an empty result set.
report_init() {
  RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-security-audit.XXXXXX")"
  USE_COLOR="$1"
  REPORT_FRAMED="${2:-false}"
}

report_cleanup() {
  rm -f "$RESULTS_FILE"
}

# Usage: report_pass id title [detail]; the check ran and found no issue.
report_pass() {
  record_result "$1" run pass "" "$2" "${3:-}" ""
}

# Usage: report_fail id severity title detail remediation; the check ran and found an issue.
# The severity is high, medium or low.
report_fail() {
  record_result "$1" run fail "$2" "$3" "$4" "$5"
}

# Usage: report_skip id title reason
report_skip() {
  record_result "$1" skipped "" "" "$2" "$3" ""
}

# Usage: report_manual id title instructions; skipped, as only you can review it.
report_manual() {
  record_result "$1" skipped "" "" "$2" "to review yourself" "$3"
}

# Usage: report_error id title detail; the check ran but could not finish.
report_error() {
  record_result "$1" error "" "" "$2" "$3" ""
}

# The section is the id prefix: "platform.filevault" belongs to "platform". The risk and impact
# come from data/risks.json. Empty or unknown values are recorded as null. The title, detail and
# remediation may hold names from the Mac, so they are kept printable.
record_result() {
  jq -cn --slurpfile risks "$ROOT_DIR/data/risks.json" \
    --arg id "$1" --arg status "$2" --arg outcome "$3" --arg severity "$4" \
    --arg title "$5" --arg detail "$6" --arg remediation "$7" \
    "$(<"$ROOT_DIR/lib/text.jq")"$'\n''{id: $id, section: ($id | split(".")[0]), title: ($title | printable),
      status: $status, outcome: ($outcome | select(. != "") // null),
      severity: ($severity | select(. != "") // null), detail: ($detail | printable),
      risk: $risks[0][$id].risk, impact: $risks[0][$id].impact, remediation: ($remediation | printable)}' \
    >>"$RESULTS_FILE"
}

# Two tables: every check, then the findings, most severe first.
# Framed to the terminal width on a terminal; plain and never cut otherwise.
print_report() {
  local width=1000
  [[ "$REPORT_FRAMED" != true ]] || width="$(terminal_width)"
  jq -rs --argjson isTerminal "$REPORT_FRAMED" --argjson useColor "$USE_COLOR" --argjson terminalWidth "$width" \
    --arg host "$(host_name)" --arg macos "$(sw_vers -productVersion)" --arg generatedAt "$(date '+%F %H:%M')" \
    "$(cat "$ROOT_DIR/lib/table.jq" "$ROOT_DIR/lib/text.jq" "$ROOT_DIR/lib/report.jq")"$'\n''(checks, findings) | table' \
    "$RESULTS_FILE"
}

# Usage: verdict_label pass|fail|skipped|error
verdict_label() {
  case "$1" in
    pass) paint green "PASS   " ;;
    fail) paint red "FAIL   " ;;
    skipped) paint dim "SKIPPED" ;;
    error) paint magenta "ERROR  " ;;
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

# Usage: has_findings_from high|medium|low; true when a finding has this severity or a higher one.
has_findings_from() {
  jq -se --arg lowest "$1" '["high", "medium", "low"] as $order
    | any(.[]; .severity as $severity | $severity != null and ($order | index($severity)) <= ($order | index($lowest)))' \
    "$RESULTS_FILE" >/dev/null
}

# Prints the pretty-printed JSON report.
write_json_report() {
  jq -n \
    --slurpfile checks "$RESULTS_FILE" \
    --arg host "$(host_name)" \
    --arg version "$(sw_vers -productVersion)" \
    --arg build "$(sw_vers -buildVersion)" \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'def counts($key): map(. as $value | {key: ., value: ($checks | map(select(.[$key] == $value)) | length)})
       | from_entries;
    {
      host: $host,
      macos: {version: $version, build: $build},
      generatedAt: $generatedAt,
      summary: {
        status: (["run", "skipped", "error"] | counts("status")),
        outcome: (["pass", "fail"] | counts("outcome")),
        severity: (["high", "medium", "low"] | counts("severity"))
      },
      checks: $checks
    }'
}

host_name() {
  scutil --get LocalHostName 2>/dev/null || hostname
}
