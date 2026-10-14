# Live log on stderr while the checks run, like docker build; source it, don't run it.
# Each finished check prints a line that stays, with its id and the commands it ran; below them, a
# live block lists the running checks, their current command and latest step note, and is redrawn
# in place. Lines span the screen width. Notes and commands may hold names from the Mac, so they are
# kept printable.

SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
MAX_RUNNING_SHOWN=6
ESC=$'\033'
# C1 control characters in UTF-8, matched as bytes so that any locale finds them
C1_CONTROLS=$'\xc2'[$'\x80'-$'\x9f']
SHOW_PROGRESS=false
SCREEN_WIDTH=80
ID_WIDTH=0
SPREAD_LINE=""
RUNNING_COMMAND=""
PRINTABLE=""
CURSOR_HIDDEN=false
LIVE_LINES=0
DONE_COUNT=0
# The frame is built in FRAME_TEXT, then written at once to avoid flicker.
FRAME_TEXT=""
ENTRY_LOGGED=()
ENTRY_NOTES=()

# $1 is "true" to show progress.
progress_init() {
  SHOW_PROGRESS="$1"
  [[ "$SHOW_PROGRESS" != true ]] || SCREEN_WIDTH="$(terminal_width)"
}

# Usage: progress_note text
# Shows text under the running check; checks call it before a slow step.
progress_note() {
  [[ -z "${PROGRESS_NOTE_FILE:-}" ]] || printf '%s\n' "$1" >"$PROGRESS_NOTE_FILE"
}

# Prints the log and redraws the live block until every check has finished.
progress_watch() {
  [[ "$SHOW_PROGRESS" == true ]] || return 0
  local frame=0 entry
  for ((entry = 0; entry < ENTRY_COUNT; entry++)); do
    [[ "${#ENTRY_IDS[entry]}" -le "$ID_WIDTH" ]] || ID_WIDTH="${#ENTRY_IDS[entry]}"
  done
  CURSOR_HIDDEN=true
  printf '%s' "${ESC}[?25l" >&2
  while :; do
    FRAME_TEXT=""
    erase_live_block
    log_finished_checks
    [[ "$DONE_COUNT" -lt "$ENTRY_COUNT" ]] || break
    add_live_block "${SPINNER_FRAMES[frame]}"
    printf '%s' "$FRAME_TEXT" >&2
    frame=$(((frame + 1) % ${#SPINNER_FRAMES[@]}))
    sleep 0.1
  done
  printf '%s' "$FRAME_TEXT" >&2
  progress_stop
}

# Erases the live block and shows the cursor again; safe to call when nothing is shown.
progress_stop() {
  FRAME_TEXT=""
  erase_live_block
  [[ "$CURSOR_HIDDEN" != true ]] || FRAME_TEXT="$FRAME_TEXT${ESC}[?25h"
  CURSOR_HIDDEN=false
  [[ -z "$FRAME_TEXT" ]] || printf '%s' "$FRAME_TEXT" >&2
}

# The cursor sits below the block, so it moves up to the block's first line and clears down.
erase_live_block() {
  [[ "$LIVE_LINES" -gt 0 ]] || return 0
  FRAME_TEXT="$FRAME_TEXT${ESC}[${LIVE_LINES}A"$'\r'"${ESC}[J"
  LIVE_LINES=0
}

# Adds a log line for each newly finished check, and counts the finished ones.
log_finished_checks() {
  local entry
  DONE_COUNT=0
  for ((entry = 0; entry < ENTRY_COUNT; entry++)); do
    [[ -e "$RUNNER_DIR/$entry.done" ]] || continue
    DONE_COUNT=$((DONE_COUNT + 1))
    [[ -z "${ENTRY_LOGGED[entry]:-}" ]] || continue
    ENTRY_LOGGED[entry]=true
    FRAME_TEXT="$FRAME_TEXT$(log_line "$entry")"$'\n'
  done
}

# Usage: log_line entry; prints "  STATUS   id   commands   Ns".
log_line() {
  local label
  label="$(verdict_label "$(check_verdict "$RUNNER_DIR/$1.ndjson")")"
  make_printable "$(ran_commands "$RUNNER_DIR/$1.commands")"
  spread_line "  ${label:-------  }  " "${ENTRY_IDS[$1]}" "$PRINTABLE" "$((SECONDS - RUN_STARTED))s"
  printf '%s' "$SPREAD_LINE"
}

# Usage: ran_commands commands_file; the commands, each once, joined by "; ", with long quoted
# programs (awk, jq) shortened to '…'.
ran_commands() {
  [[ -e "$1" ]] || return 0
  awk '!seen[$0]++' "$1" | sed -E "s/'[^']{20,}'/'…'/g" | paste -sd ';' - | sed 's/;/; /g'
}

# Usage: spread_line start id text end
# Sets SPREAD_LINE to start and id, padded to the widest id, then text and end, dimmed, with end at
# the right edge; text is cut to fit the screen width. Forks nothing, as the live block calls it.
spread_line() {
  local id text="$3" room padding on="" off=""
  printf -v id "%-${ID_WIDTH}s" "$2"
  room=$((SCREEN_WIDTH - 1 - ${#1} - ID_WIDTH - 2 - ${#4} - 2))
  [[ "$room" -gt 1 ]] || room=1
  [[ "${#text}" -le "$room" ]] || text="${text:0:$((room - 1))}…"
  # padded here, as printf counts bytes and … takes three
  printf -v padding '%*s' $((room - ${#text})) ""
  [[ "$USE_COLOR" != true ]] || { on="${ESC}[2m"; off="${ESC}[0m"; }
  SPREAD_LINE="$1$id  $on$text$padding  $4$off"
}

# Usage: check_verdict results_file; the worst of fail, error, pass and skipped among the check's results.
check_verdict() {
  local results
  [[ -e "$1" ]] || return 0
  results="$(<"$1")"
  case "$results" in
    *'"outcome":"fail"'*) echo fail ;;
    *'"status":"error"'*) echo error ;;
    *'"outcome":"pass"'*) echo pass ;;
    *'"status":"skipped"'*) echo skipped ;;
  esac
}

# Usage: add_live_block spinner_frame
add_live_block() {
  local entry shown=0 running=$((ENTRY_COUNT - DONE_COUNT))
  add_live_line "[+] Auditing $((SECONDS - RUN_STARTED))s · $DONE_COUNT/$ENTRY_COUNT done"
  for ((entry = 0; entry < ENTRY_COUNT && shown < MAX_RUNNING_SHOWN; entry++)); do
    [[ ! -e "$RUNNER_DIR/$entry.done" ]] || continue
    shown=$((shown + 1))
    read_running_command "$entry"
    spread_line " $1 " "${ENTRY_IDS[entry]}" "$RUNNING_COMMAND" "$((SECONDS - RUN_STARTED))s"
    add_fitted_line "$SPREAD_LINE"
    read_note "$entry"
    [[ -z "${ENTRY_NOTES[entry]:-}" ]] || add_live_line "     ${ENTRY_NOTES[entry]}"
  done
  [[ "$running" -le "$shown" ]] || add_live_line " … $((running - shown)) more running"
}

read_running_command() {
  local running=""
  [[ ! -e "$RUNNER_DIR/$1.running" ]] || IFS= read -r running <"$RUNNER_DIR/$1.running"
  make_printable "$running"
  RUNNING_COMMAND="$PRINTABLE"
}

# Keeps the previous note when the check is rewriting its note file.
read_note() {
  local note=""
  [[ -e "$RUNNER_DIR/$1.note" ]] || return 0
  IFS= read -r note <"$RUNNER_DIR/$1.note"
  make_printable "$note"
  [[ -z "$PRINTABLE" ]] || ENTRY_NOTES[$1]="$PRINTABLE"
}

# Usage: make_printable text
# Sets PRINTABLE to text without the control characters a terminal would run: tabs and newlines
# become spaces, the others go. Forks nothing, as the live block calls it.
make_printable() {
  PRINTABLE="${1//[$'\t\n']/ }"
  PRINTABLE="${PRINTABLE//[[:cntrl:]]/}"
  PRINTABLE="${PRINTABLE//$C1_CONTROLS/}"
}

# Cut to the screen width, so no line wraps and the cursor moves stay right.
add_live_line() {
  add_fitted_line "${1:0:$((SCREEN_WIDTH - 1))}"
}

add_fitted_line() {
  FRAME_TEXT="$FRAME_TEXT$1"$'\n'
  LIVE_LINES=$((LIVE_LINES + 1))
}
