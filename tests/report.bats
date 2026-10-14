#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/report.sh
}

given_one_result_of_each_kind() {
  report_pass test.pass "Passing check" "pass detail"
  report_fail test.high high "High check" "high detail" "high fix"
  report_fail test.low low "Low check" "low detail" "low fix"
  report_skip test.skip "Skipped check" "skip reason"
  report_manual test.manual "Manual check" "manual steps"
  report_error test.error "Broken check" "error detail"
}

# A name that erases its own line, then an 8-bit CSI, a bell and a DEL.
HOSTILE_NAME=$'evil\033[2K\033[1A\xc2\x9b31m\a\x7f.app'

# Prints the control characters of stdin, other than its newlines.
control_characters() {
  LC_ALL=C tr -d '\n' | LC_ALL=C grep -Eo $'[\x01-\x1f\x7f]|\xc2[\x80-\x9f]'
}

# Usage: report_part title
# Prints the rows of the plain table "title (n)": the lines between its two rules, or "none".
report_part() {
  print_report | awk -v title=" $1 (" '
    index($0, title) == 1 { inside = 1; next }
    inside && /^ ─/ { rules++; if (rules == 2) exit; next }
    inside && rules == 1' | sed 's/^ //'
}

# Usage: framed_report width; the report as on a terminal of that width, without colour.
framed_report() {
  REPORT_FRAMED=true COLUMNS="$1" print_report
}

# Prints the width of each line of stdin, in characters.
line_widths() {
  while IFS= read -r line; do echo "${#line}"; done
}

@test "the checks table lists every check in run order" {
  given_one_result_of_each_kind

  [[ "$(report_part "Checks" | grep -o '[A-Z][a-z]* check' | paste -sd , -)" == \
    "Passing check,High check,Low check,Skipped check,Manual check,Broken check" ]]
}

@test "a check that ran shows its status, outcome and id" {
  report_pass platform.filevault "FileVault disk encryption on" ""

  [[ "$(report_part "Checks")" == "RUN     PASS     platform.filevault  FileVault disk encryption on" ]]
}

@test "a failed check shows its outcome and detail" {
  report_fail test.high high "High check" "high detail" "high fix"

  [[ "$(report_part "Checks")" == "RUN     FAIL     test.high  High check  high detail" ]]
}

@test "a skipped check says why" {
  report_skip test.skip "Skipped check" "skip reason"

  [[ "$(report_part "Checks")" == "SKIPPED           test.skip  Skipped check  skip reason" ]]
}

@test "a manual check says what to review" {
  report_manual test.manual "Manual check" "manual steps"

  [[ "$(report_part "Checks")" == *"SKIPPED"*"to review yourself → manual steps" ]]
}

@test "a check in error shows the error" {
  report_error test.error "Broken check" "error detail"

  [[ "$(report_part "Checks")" == "ERROR            test.error  Broken check  error detail" ]]
}

@test "the checks footer counts statuses and outcomes" {
  given_one_result_of_each_kind

  print_report | grep -qx " 3 run  ·  2 skipped  ·  1 error  ·  1 pass  ·  2 fail"
}

@test "findings list failed checks only, most severe first" {
  report_fail test.low low "Low check" "" ""
  report_fail test.high high "High check" "" ""
  report_fail test.medium medium "Medium check" "" ""
  report_pass test.pass "Passing check"

  [[ "$(report_part "Findings" | grep -o '^[A-Z]* *[a-z.]* *[A-Z][a-z]* check' | awk '{print $1 ":" $3}' | paste -sd , -)" == \
    "HIGH:High,MEDIUM:Medium,LOW:Low" ]]
}

@test "findings show the detail and the fix" {
  report_fail test.high high "High check" "high detail" "high fix"

  [[ "$(report_part "Findings")" == *"high detail"*"→ high fix"* ]]
}

@test "findings say why they matter" {
  report_fail network.firewall high "Application firewall on" "Firewall is disabled" "turn it on"

  [[ "$(report_part "Findings")" == *"every app and service listening on the network"* ]]
}

@test "findings are counted in the title" {
  given_one_result_of_each_kind

  print_report | grep -qx " Findings (2)"
}

@test "no findings say none" {
  report_pass test.pass "Passing check" ""

  [[ "$(report_part "Findings")" == "none" ]]
}

@test "the findings footer counts severities" {
  given_one_result_of_each_kind

  [[ "$(print_report | tail -1)" == " 1 high  ·  1 low" ]]
}

@test "a framed report opens and closes a frame per table" {
  given_one_result_of_each_kind

  [[ "$(framed_report 80 | grep -o '^╭─ [A-Za-z]*' | paste -sd , -)" == "╭─ Checks,╭─ Findings" ]]
  [[ "$(framed_report 80 | grep -c '^╰─')" == 2 ]]
}

@test "every framed line fills the terminal width" {
  given_one_result_of_each_kind
  report_fail test.long medium "Long check" "$(printf 'detail %.0s' {1..30})" "$(printf 'fix %.0s' {1..40})"

  [[ "$(framed_report 60 | grep -v '^$' | line_widths | sort -u)" == 60 ]]
}

@test "a framed report cuts a long fix" {
  report_fail test.long low "Long check" "" "$(printf 'fix %.0s' {1..40})end"

  [[ "$(framed_report 80)" == *"→ fix fix"*"…"* && "$(framed_report 80)" != *"fix end"* ]]
}

@test "a plain report keeps a long fix whole" {
  report_fail test.long low "Long check" "" "$(printf 'fix %.0s' {1..40})end"

  [[ "$(report_part "Findings")" == *"fix fix end" ]]
}

@test "a framed report without colour has no colour codes" {
  given_one_result_of_each_kind

  [[ "$(framed_report 80)" != *$'\033['* ]]
}

@test "a coloured report paints outcomes and severities" {
  report_fail test.high high "High check" "" ""
  USE_COLOR=true

  [[ "$(framed_report 80)" == *$'\033[31mFAIL\033[0m'*$'\033[31mHIGH\033[0m'* ]]
}

@test "a recorded result keeps its text without control characters" {
  report_fail test.hostile high "$HOSTILE_NAME" "$HOSTILE_NAME" "$HOSTILE_NAME"

  [[ "$(jq -r '[.title, .detail, .remediation] | unique[]' "$RESULTS_FILE")" == "evil[2K[1A31m.app" ]]
}

@test "a recorded result turns tabs and newlines into spaces" {
  report_fail test.spaced high "Spaced check" $'one\ttwo\nthree' ""

  [[ "$(detail_of test.spaced)" == "one two three" ]]
}

@test "a plain report prints no control characters from a result" {
  report_fail test.hostile high "$HOSTILE_NAME" "$HOSTILE_NAME" "$HOSTILE_NAME"

  [[ -z "$(print_report | control_characters)" ]]
}

@test "a framed report prints no control characters from a result" {
  report_fail test.hostile high "$HOSTILE_NAME" "$HOSTILE_NAME" "$HOSTILE_NAME"

  [[ -z "$(framed_report 80 | control_characters)" ]]
}

@test "wide characters keep the frame lined up" {
  report_fail test.wide medium "Emoji 🔑 and 漢字 in a title" "" ""

  [[ "$(framed_report 70 | grep -v '^$' | sed 's/[🔑漢字]/&&/g' | line_widths | sort -u)" == 70 ]]
}
