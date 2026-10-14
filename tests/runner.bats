#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/runner.sh
  runner_init
  CHECK_SECTION=test
  OUTPUT_FILE="$BATS_TEST_TMPDIR/output"
  FLAG_FILE="$BATS_TEST_TMPDIR/flag"
}

teardown() {
  runner_cleanup
}

check_test_slow() {
  sleep 0.3
  report_pass test.slow "Slow check"
}

check_test_fast() {
  report_pass test.fast "Fast check"
}

# Passes only if check_test_flag runs while it waits.
check_test_waiting() {
  local tries
  for tries in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ ! -e "$FLAG_FILE" ]] || { report_pass test.waiting "Saw the flag"; return; }
    sleep 0.1
  done
  report_fail test.waiting high "Saw the flag" "" ""
}

check_test_flag() {
  : >"$FLAG_FILE"
  report_pass test.flag "Raised the flag"
}

check_test_mixed() {
  report_pass test.one "Fine"
  report_fail test.two low "Not fine" "" ""
}

check_test_noting() {
  progress_note "step 1 of 2"
  progress_note "step 2 of 2"
  sleep 0.3
}

check_test_noting_hostile() {
  progress_note $'evil\033[2K\033[1A\xc2\x9b.app'
  sleep 0.3
}

check_test_complaining() {
  echo "probe complained" >&2
}

check_test_hostile_output() {
  printf '\033[2Jwiped\n'
  printf '\033[2Jwiped\n' >&2
}

check_test_silent() {
  echo "probe crashed" >&2
}

check_test_probing() {
  local file="$HOME/.probe rc" token="s3cret"
  probe-tool --status "$file"
  probe-tool --token "$token"
  echo hello | tr a-z A-Z >/dev/null
  grep -c x "$HOME/notes" >/dev/null
  PROBE_QUIET=1 probe-tool --quiet
  report_pass test.probing "Probing"
}

# Runs a command for 0.3 s.
check_test_waiting_on_tool() {
  slow-tool --wait
  report_pass test.waiting-on-tool "Waiting"
}

given_probe_tools() {
  stub_command probe-tool "ok"
  stub_script slow-tool <<<'sleep 0.3'
  echo "x" >"$HOME/notes"
}

# Prints the width of each line of stdin, in characters.
line_widths() {
  while IFS= read -r line; do echo "${#line}"; done
}

check_test_long() {
  sleep 31.7
}

# Slow enough for a new stub's first run, which macOS scans first.
check_test_root() {
  sleep 1
  : >"$HOME/root-done"
  report_pass test.root "Root check"
}

# Passes only if the root check finished first.
check_test_after_root() {
  if [[ -e "$HOME/root-done" ]]; then
    report_pass test.after-root "Ran after the root check"
  else
    report_fail test.after-root low "Ran after the root check" "ran alongside it" "wait"
  fi
}

# Passes only if sudo forgot its credentials first.
check_test_after_drop() {
  if [[ "$(tail -1 "$SUDO_LOG")" == -k ]]; then
    report_pass test.after-drop "Ran after sudo -k"
  else
    report_fail test.after-drop low "Ran after sudo -k" "sudo still usable" "drop it"
  fi
}

# Passes when user-tool is on the PATH.
check_test_user_tool() {
  if has_command user-tool; then
    report_pass test.user-tool "Found user-tool"
  else
    report_fail test.user-tool low "Found user-tool" "not on the PATH" "add it"
  fi
}

check_test_root_user_tool() {
  if has_command user-tool; then
    report_pass test.root-user-tool "Found user-tool"
  else
    report_fail test.root-user-tool low "Found user-tool" "not on the PATH" "add it"
  fi
}

# Usage: given_logged_sudo cached|refused; sudo logs its arguments to $SUDO_LOG.
given_logged_sudo() {
  SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  : >"$SUDO_LOG"
  stub_script sudo <<STUB
echo "\$*" >>"$SUDO_LOG"
[[ "$1" == cached ]] || exit 1
[[ "\$1" == -n ]] && shift
[[ "\$1" == -k ]] || "\$@"
STUB
}

# A tool found only on the PATH the audit started with.
given_user_tool() {
  mkdir -p "$BATS_TEST_TMPDIR/user-bin"
  printf '#!/bin/bash\n' >"$BATS_TEST_TMPDIR/user-bin/user-tool"
  chmod +x "$BATS_TEST_TMPDIR/user-bin/user-tool"
  USER_PATH="$PATH:$BATS_TEST_TMPDIR/user-bin"
}

@test "checks run at the same time" {
  run_check "waiting" check_test_waiting
  run_check "flag" check_test_flag

  collect_results >/dev/null

  [[ "$(result_of test.waiting)" == pass ]]
}

@test "results are recorded in queue order" {
  run_check "something slow" check_test_slow
  run_check "something fast" check_test_fast

  collect_results >/dev/null

  [[ "$(jq -r .id "$RESULTS_FILE" | paste -sd , -)" == "test.slow,test.fast" ]]
}

@test "check errors go to stderr" {
  run_check "complaining" check_test_complaining

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == "probe complained" ]]
}

@test "a check's output goes to stderr, without control characters" {
  run_check "hostile output" check_test_hostile_output

  collect_results 2>"$OUTPUT_FILE" >"$BATS_TEST_TMPDIR/stdout"

  [[ "$(cat "$OUTPUT_FILE")" == $'[2Jwiped\n[2Jwiped' && ! -s "$BATS_TEST_TMPDIR/stdout" ]]
}

@test "a check without a result is an error" {
  run_check "silent" check_test_silent

  collect_results 2>/dev/null >/dev/null

  [[ "$(result_of test.silent)" == error && "$(detail_of test.silent)" == "the check reported no result: probe crashed" ]]
}

@test "a finished check prints a log line with its id" {
  progress_init true
  run_check "something fast" check_test_fast

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *"  PASS     test.fast  "* ]]
}

@test "the log line shows the commands the check ran" {
  given_probe_tools
  progress_init true
  SCREEN_WIDTH=200
  run_check "probing" check_test_probing

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *"  PASS     test.probing  probe-tool --status ~/\".probe rc\"; probe-tool --token"* ]]
}

@test "log lines span the screen width, with the time at the right edge" {
  given_probe_tools
  progress_init true
  SCREEN_WIDTH=100
  run_check "probing" check_test_probing

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  # the live block's erase codes come first
  [[ "$(grep PASS "$OUTPUT_FILE" | sed $'s/^.*\033\\[J//' | line_widths)" == 99 && "$(grep PASS "$OUTPUT_FILE")" == *" "[0-9]s ]]
}

@test "the commands a check ran are kept with its results" {
  given_probe_tools
  run_check "probing" check_test_probing

  collect_results >/dev/null

  [[ "$(jq -r '.commands[]' "$RESULTS_FILE")" == 'probe-tool --status ~/".probe rc"
probe-tool --token "$token"
grep -c x ~/notes
PROBE_QUIET=1 probe-tool --quiet' ]]
}

@test "a value that is not a path is not shown" {
  given_probe_tools
  run_check "probing" check_test_probing

  collect_results >/dev/null

  [[ "$(cat "$RESULTS_FILE")" != *s3cret* ]]
}

@test "text tools are recorded only when they read a file" {
  given_probe_tools
  run_check "probing" check_test_probing

  collect_results >/dev/null

  [[ "$(jq -r '.commands[]' "$RESULTS_FILE")" != *tr* ]]
}

@test "a running check shows the command it runs" {
  given_probe_tools
  progress_init true
  run_check "waiting" check_test_waiting_on_tool

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *" test.waiting-on-tool  slow-tool --wait "* ]]
}

@test "the log line shows the worst result of the check" {
  progress_init true
  run_check "mixed" check_test_mixed

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *"FAIL"*"mixed"* ]]
}

@test "running checks are shown below the log" {
  progress_init true
  run_check "something slow" check_test_slow

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *"[+] Auditing "[0-9]"s · 0/1 done"$'\n'*" test.slow  "* ]]
}

@test "a running check shows its latest note" {
  progress_init true
  run_check "noting" check_test_noting

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *" test.noting "*$'\n'"     step 2 of 2"* ]]
}

@test "a running check shows its note without control characters" {
  progress_init true
  run_check "noting" check_test_noting_hostile

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *$'\n'"     evil[2K[1A.app"$'\n'* ]]
}

@test "running checks beyond the limit are counted" {
  progress_init true
  MAX_RUNNING_SHOWN=1
  run_check "first" check_test_slow
  run_check "second" check_test_slow
  run_check "third" check_test_slow

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *"… 2 more running"* ]]
}

@test "the live block is erased and the cursor shown once the checks are done" {
  progress_init true
  run_check "something slow" check_test_slow

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *$'\033[J'*"test.slow"*$'\033[?25h' ]]
}

@test "notes are not written when progress is off" {
  run_check "noting" check_test_noting

  collect_results 2>/dev/null >/dev/null

  [[ ! -e "$RUNNER_DIR/0.note" ]]
}

@test "checks print nothing while they run" {
  run_check "something fast" check_test_fast

  collect_results >"$OUTPUT_FILE"

  [[ ! -s "$OUTPUT_FILE" ]]
}

@test "no progress when turned off" {
  run_check "something slow" check_test_slow

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ ! -s "$OUTPUT_FILE" ]]
}

@test "with cached sudo, the other checks wait for the root checks" {
  given_logged_sudo cached
  run_root_check "root" check_test_root
  run_check "after root" check_test_after_root

  collect_results >/dev/null

  [[ "$(result_of test.after-root)" == pass ]]
}

@test "with cached sudo, the other checks start once sudo is dropped" {
  given_logged_sudo cached
  run_root_check "root" check_test_root
  run_check "after drop" check_test_after_drop

  collect_results >/dev/null

  [[ "$(result_of test.after-drop)" == pass ]]
}

@test "without cached sudo, the other checks don't wait" {
  given_logged_sudo refused
  run_root_check "root" check_test_root
  run_check "after root" check_test_after_root

  collect_results >/dev/null

  [[ "$(result_of test.after-root)" == "fail low" ]]
}

@test "without cached sudo, there is nothing to drop" {
  given_logged_sudo refused
  run_root_check "root" check_test_root

  collect_results >/dev/null

  [[ "$(cat "$SUDO_LOG")" != *-k* ]]
}

@test "the other checks get the user's PATH back" {
  given_user_tool
  run_check "user tool" check_test_user_tool

  collect_results >/dev/null

  [[ "$(result_of test.user-tool)" == pass ]]
}

@test "root checks keep the system PATH" {
  given_user_tool
  run_root_check "root user tool" check_test_root_user_tool

  collect_results >/dev/null

  [[ "$(result_of test.root-user-tool)" == "fail low" ]]
}

@test "a check waiting for the root checks says so" {
  SCREEN_WIDTH=200
  progress_init true
  given_logged_sudo cached
  run_root_check "root" check_test_root
  run_check "after root" check_test_after_root

  collect_results 2>"$OUTPUT_FILE" >/dev/null

  [[ "$(cat "$OUTPUT_FILE")" == *" test.after-root  waiting for the root-only checks "* ]]
}

@test "the audit gets the user's PATH back once the checks are done" {
  given_user_tool
  run_check "something fast" check_test_fast

  collect_results >/dev/null

  has_command user-tool
}

@test "cleanup before the root checks are done forgets sudo's credentials" {
  given_logged_sudo cached
  run_root_check "long" check_test_long

  runner_cleanup

  [[ "$(tail -1 "$SUDO_LOG")" == -k ]]
}

@test "cleanup after sudo was dropped leaves sudo alone" {
  given_logged_sudo refused
  run_check "something fast" check_test_fast
  collect_results >/dev/null
  : >"$SUDO_LOG"

  runner_cleanup

  [[ ! -s "$SUDO_LOG" ]]
}

@test "cleanup stops running checks and their commands" {
  run_root_check "long" check_test_long
  until pgrep -f "sleep 31.7" >/dev/null; do sleep 0.1; done

  runner_cleanup
  sleep 0.2

  ! pgrep -f "sleep 31.7"
}
