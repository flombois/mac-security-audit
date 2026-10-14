# Runs the checks in parallel and collects their results in order; source it, don't run it.
# Each queued check n keeps its output in $RUNNER_DIR/n.out, n.err and n.ndjson, its step note in
# n.note, the commands it ran in n.commands and the latest one in n.running; n.done appears when it
# has finished.
# While sudo has cached credentials, only the root checks run, with macOS's own tools: the other
# checks wait until they are done and sudo is dropped, so no other program can use sudo.

# shellcheck disable=SC2034 # the ids and start time are read by lib/progress.sh
RUNNER_DIR=""
ENTRY_COUNT=0
ENTRY_PIDS=()
ENTRY_IDS=()
RUN_STARTED=0
ROOT_ENTRIES=""
SUDO_DROPPER_PID=""
USER_PATH="${USER_PATH:-$PATH}"
# Commands that only reshape text or names are left out of the recorded commands; text readers are
# recorded when they read a file.
TEXT_TOOLS=" tr sort uniq head tail cut wc tee paste comm column fold date mktemp basename dirname realpath sleep printf echo test env true false "
TEXT_READERS=" awk sed grep egrep jq cat xargs "
SHELL_WORDS=" $(compgen -b | tr '\n' ' ')$(compgen -k | tr '\n' ' ') "

runner_init() {
  RUNNER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-security-audit.XXXXXX")"
  RUN_STARTED=$SECONDS
}

# Usage: run_check label check_function
# Starts the check in the background; collect_results gathers its results. The check reports under
# its id, made from $CHECK_SECTION and the function name (check_id).
run_check() {
  queue_check user "$@"
}

# Usage: run_root_check label check_function; for the checks that use sudo, and only those.
run_root_check() {
  queue_check root "$@"
}

# Usage: queue_check root|user label check_function
queue_check() {
  local kind="$1" entry="$RUNNER_DIR/$ENTRY_COUNT" id
  shift
  id="$(check_id "$2")"
  [[ "$kind" != root ]] || ROOT_ENTRIES="$ROOT_ENTRIES $ENTRY_COUNT"
  (
    [[ "$kind" == root ]] || wait_for_sudo_drop "$entry"
    # exported so that the check's child processes can post notes too
    [[ "$SHOW_PROGRESS" != true ]] || export PROGRESS_NOTE_FILE="$entry.note"
    : >"$entry.commands"
    set -T
    # the arguments are those of the function the command runs in, for its $1, $2…
    trap 'record_command ${1+"$@"}' DEBUG
    RESULTS_FILE="$entry.ndjson" COMMANDS_FILE="$entry.commands" "$2" >"$entry.out" 2>"$entry.err" </dev/null
    trap - DEBUG
    set +T
    [[ -s "$entry.ndjson" ]] ||
      RESULTS_FILE="$entry.ndjson" report_error "$id" "$1" "$(no_result_detail "$entry.err")"
    attach_commands "$entry"
    : >"$entry.done"
  ) &
  ENTRY_PIDS[ENTRY_COUNT]="$!"
  ENTRY_IDS[ENTRY_COUNT]="$id"
  ENTRY_COUNT=$((ENTRY_COUNT + 1))
}

# Usage: wait_for_sudo_drop entry; then gives the check the user's PATH back.
wait_for_sudo_drop() {
  [[ "$SHOW_PROGRESS" != true ]] || echo "waiting for the root-only checks" >"$1.running"
  until [[ -e "$RUNNER_DIR/sudo-dropped" ]]; do sleep 0.1; done
  rm -f "$1.running"
  PATH="$USER_PATH"
}

# With cached credentials, waits for the root checks, then forgets the credentials.
drop_sudo_after_root_checks() {
  local entry
  if sudo_available; then
    for entry in $ROOT_ENTRIES; do
      until [[ -e "$RUNNER_DIR/$entry.done" ]]; do sleep 0.1; done
    done
    sudo -k
  fi
  : >"$RUNNER_DIR/sudo-dropped"
}

# The check's DEBUG trap: logs each program it runs, as written, with path variables filled in.
# It runs before every command, so it forks nothing; its locals are prefixed to leave the check's visible.
record_command() {
  local recorded_command="$BASH_COMMAND" recorded_rest recorded_program
  RECORDED_ARGS=("$@")
  case "${BASH_SOURCE[1]:-}" in *lib/report.sh | *lib/progress.sh | *lib/runner.sh) return 0 ;; esac
  recorded_rest="$recorded_command"
  recorded_program="${recorded_rest%%[[:space:]]*}"
  # in NAME=value program…, the program follows the variables
  while is_plain_assignment "$recorded_program" && [[ "$recorded_rest" == *[[:space:]]* ]]; do
    recorded_rest="${recorded_rest#*[[:space:]]}"
    recorded_program="${recorded_rest%%[[:space:]]*}"
  done
  recorded_program="${recorded_program//\"/}"
  case "$recorded_program" in
    *=* | '(('* | '') return 0 ;;
    '$'[1-9]) recorded_program="${RECORDED_ARGS[${recorded_program#$} - 1]-}" ;;
    '$'*)
      recorded_program="${recorded_program#$}"
      recorded_program="${recorded_program#\{}"
      recorded_program="${recorded_program%\}}"
      is_variable_name "$recorded_program" || return 0
      recorded_program="${!recorded_program-}"
      ;;
  esac
  [[ "$SHELL_WORDS" != *" $recorded_program "* && "$TEXT_TOOLS" != *" ${recorded_program##*/} "* ]] || return 0
  ! declare -F "$recorded_program" >/dev/null || return 0
  drop_redirections
  expand_variables "$recorded_command"
  [[ "$TEXT_READERS" != *" ${recorded_program##*/} "* || "$EXPANDED_OUTSIDE_QUOTES" == *[[:space:]][/~]* ]] || return 0
  printf '%s\n' "$EXPANDED" >>"$COMMANDS_FILE"
  [[ "$SHOW_PROGRESS" != true ]] || printf '%s\n' "$EXPANDED" >"${COMMANDS_FILE%.commands}.running"
}

# Drops the redirections that only silence the command from recorded_command.
drop_redirections() {
  local redirection
  for redirection in ' > /dev/null' ' 2> /dev/null' ' &> /dev/null' ' < /dev/null' ' 2>&1'; do
    recorded_command="${recorded_command//"$redirection"/}"
  done
}

# Usage: expand_variables text
# Sets EXPANDED to text on one line, with each $name or ${name} outside single quotes replaced by its
# value when that is a path, shortened to ~; other values may be secret, so they stay hidden.
# EXPANDED_OUTSIDE_QUOTES holds the same, without the single-quoted parts.
expand_variables() {
  local expand_rest="${1//[$'\n\t']/ }" expand_part
  EXPANDED=""
  EXPANDED_OUTSIDE_QUOTES=""
  while [[ -n "$expand_rest" ]]; do
    expand_part="${expand_rest%%\'*}"
    expand_rest="${expand_rest:${#expand_part}}"
    expand_outside "$expand_part"
    [[ -n "$expand_rest" ]] || break
    expand_part="${expand_rest#\'}"
    expand_part="'${expand_part%%\'*}'"
    EXPANDED+="$expand_part"
    expand_rest="${expand_rest:${#expand_part}}"
  done
  while [[ "$EXPANDED" == *"  "* ]]; do EXPANDED="${EXPANDED//  / }"; done
  EXPANDED="${EXPANDED% }"
}

expand_outside() {
  local outside_rest="$1" outside_name outside_value outside_text="" tilde="~"
  while [[ "$outside_rest" == *'$'* ]]; do
    outside_text+="${outside_rest%%\$*}\$"
    outside_rest="${outside_rest#*\$}"
    if [[ "$outside_rest" == '{'*'}'* ]]; then
      outside_name="${outside_rest#\{}"
      outside_name="${outside_name%%\}*}"
      is_variable_name "$outside_name" || continue
      outside_rest="${outside_rest#*\}}"
    else
      outside_name="${outside_rest%%[!A-Za-z0-9_]*}"
      [[ "$outside_name" != [1-9]* ]] || outside_name="${outside_name:0:1}"
      is_variable_name "$outside_name" || continue
      outside_rest="${outside_rest:${#outside_name}}"
    fi
    case "$outside_name" in
      [1-9]) outside_value="${RECORDED_ARGS[outside_name - 1]-}" ;;
      *) outside_value="${!outside_name-}" ;;
    esac
    if [[ "$outside_value" == /* && "$outside_value" != *$'\n'* ]]; then
      outside_text="${outside_text%\$}${outside_value//"$HOME"/$tilde}"
    else
      outside_text+="$outside_name"
    fi
  done
  tidy_path_quotes "$outside_text$outside_rest"
  EXPANDED+="$TIDIED"
  EXPANDED_OUTSIDE_QUOTES+=" $TIDIED"
}

# Sets TIDIED to text with its quoted paths written as one would type them: "~/.ssh" as ~/.ssh,
# and "~/My Folder" as ~/"My Folder".
tidy_path_quotes() {
  local tidy_rest="$1" tidy_quoted
  TIDIED=""
  while [[ "$tidy_rest" == *'"'*'"'* ]]; do
    TIDIED+="${tidy_rest%%\"*}"
    tidy_rest="${tidy_rest#*\"}"
    tidy_quoted="${tidy_rest%%\"*}"
    tidy_rest="${tidy_rest#*\"}"
    case "$tidy_quoted" in
      '~/'*[[:space:]\'\$\\\`*?]*) TIDIED+="~/\"${tidy_quoted#\~/}\"" ;;
      /*[[:space:]\'\$\\\`*?]* | '~'*[[:space:]\'\$\\\`*?]*) TIDIED+="\"$tidy_quoted\"" ;;
      [/~]*) TIDIED+="$tidy_quoted" ;;
      *) TIDIED+="\"$tidy_quoted\"" ;;
    esac
  done
  TIDIED+="$tidy_rest"
}

# NAME=value, with a value that needs no quotes or expansion.
is_plain_assignment() {
  case "$1" in [A-Za-z_]*=*) ;; *) return 1 ;; esac
  is_variable_name "${1%%=*}" && [[ "${1#*=}" != *[\'\"\$\`\(]* ]]
}

# A name, or a positional parameter from 1 to 9.
is_variable_name() {
  case "$1" in [1-9]) return 0 ;; '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;; esac
}

# Adds the commands the check ran, each once and in order, to its results.
attach_commands() {
  awk '!seen[$0]++' "$1.commands" >"$1.unique"
  jq -c --rawfile commands "$1.unique" '. + {commands: ($commands | split("\n") | map(select(. != "")))}' \
    "$1.ndjson" >"$1.with-commands" && mv "$1.with-commands" "$1.ndjson"
}

# check_platform_sip in section platform is platform.sip; check_dev_ides in dev-tooling is dev-tooling.ides.
check_id() {
  local section="${CHECK_SECTION:-check}" name="${1#check_}"
  name="${name#"${section//-/_}"_}"
  name="${name#"${section%%-*}"_}"
  echo "$section.${name//_/-}"
}

# Usage: no_result_detail stderr_file
no_result_detail() {
  local message=""
  [[ ! -s "$1" ]] || message="$(head -1 "$1")"
  echo "the check reported no result${message:+: $message}"
}

# Shows the progress, then adds the results to $RESULTS_FILE in queue order. Anything a check
# prints goes to stderr, as stdout is for the report.
collect_results() {
  local entry
  drop_sudo_after_root_checks &
  SUDO_DROPPER_PID="$!"
  progress_watch
  for ((entry = 0; entry < ENTRY_COUNT; entry++)); do
    wait "${ENTRY_PIDS[$entry]}" || true
    print_printable "$RUNNER_DIR/$entry.out" >&2
    print_printable "$RUNNER_DIR/$entry.err" >&2
    cat_if_present "$RUNNER_DIR/$entry.ndjson" >>"$RESULTS_FILE"
  done
  wait "$SUDO_DROPPER_PID" || true
  SUDO_DROPPER_PID=""
  PATH="$USER_PATH"
}

cat_if_present() {
  [[ ! -e "$1" ]] || cat "$1"
}

# Prints a check's output without the control characters a terminal would run (lib/text.jq).
print_printable() {
  [[ ! -s "$1" ]] || jq -Rr "$(<"$ROOT_DIR/lib/text.jq")"$'\n''printable' "$1"
}

# Stops the checks still running, forgets sudo's credentials if that didn't happen yet, and
# removes their output.
runner_cleanup() {
  stop_running_checks 2>/dev/null # hides bash's "Terminated" notices
  [[ -z "$RUNNER_DIR" || -e "$RUNNER_DIR/sudo-dropped" ]] || sudo -k 2>/dev/null || true
  rm -rf "$RUNNER_DIR"
}

stop_running_checks() {
  local entry pid
  [[ -z "$SUDO_DROPPER_PID" ]] || kill_process_tree "$SUDO_DROPPER_PID"
  for ((entry = 0; entry < ENTRY_COUNT; entry++)); do
    pid="${ENTRY_PIDS[$entry]}"
    [[ -e "$RUNNER_DIR/$entry.done" ]] && continue
    kill_process_tree "$pid"
    wait "$pid" || true
  done
}

# Background checks ignore Ctrl-C, so they are stopped with SIGTERM.
kill_process_tree() {
  # shellcheck disable=SC2046 # one pid per word
  kill $(process_tree "$1") 2>/dev/null
}

# Prints $1 and the ids of all its descendants.
process_tree() {
  local child
  echo "$1"
  for child in $(pgrep -P "$1"); do
    process_tree "$child"
  done
}
