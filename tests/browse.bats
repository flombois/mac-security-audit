#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/report.sh
  export BROWSE_COLOR=false
}

given_results() {
  report_pass test.pass "Passing check" "pass detail"
  report_fail test.low low "Low check" "low detail" "low fix"
  report_fail test.high high "High check" "high detail" "high fix"
  report_skip test.skip "Skipped check" "skip reason"
}

# Usage: browse action [index]
browse() {
  "$ROOT_DIR/lib/browse.sh" "$1" "$RESULTS_FILE" "${2:-}"
}

@test "the findings list holds failed checks, most severe first, keyed by their index" {
  given_results

  [[ "$(browse findings | cut -f 1)" == $'2\n1' ]]
}

@test "a listed finding shows its severity, id, title and detail" {
  given_results

  [[ "$(browse findings | head -1)" == $'2\tHIGH     test.high  High check  high detail' ]]
}

@test "the checks list holds every check in run order" {
  given_results

  [[ "$(browse checks | cut -f 1 | paste -sd , -)" == "0,1,2,3" ]]
}

@test "the preview shows the detail, the fix and the commands run" {
  report_fail test.high high "High check" "high detail" "high fix"
  jq -c '. + {commands: ["probe --status"]}' "$RESULTS_FILE" >"$RESULTS_FILE.new" && mv "$RESULTS_FILE.new" "$RESULTS_FILE"

  [[ "$(browse preview 0)" == *"RUN  ·  FAIL  ·  HIGH"*"Detail"*"high detail"*"Fix"*"high fix"*"Commands run"*'$ probe --status'* ]]
}

@test "the preview shows the commands run without control characters" {
  report_fail test.high high "High check" "" ""
  jq -c '. + {commands: ["codesign -dv /Applications/evil\u001b[2K.app"]}' "$RESULTS_FILE" >"$RESULTS_FILE.new" &&
    mv "$RESULTS_FILE.new" "$RESULTS_FILE"

  [[ "$(browse preview 0)" == *'$ codesign -dv /Applications/evil[2K.app'* ]]
}

@test "the preview says why a check matters" {
  report_fail network.firewall high "Application firewall on" "Firewall is disabled" "turn it on"

  [[ "$(browse preview 0)" == *"Why it matters"*"every app and service"*"Impact"*"café, hotel"* ]]
}

@test "the preview of an empty list is empty" {
  given_results

  [[ -z "$(browse preview "")" ]]
}
