#!/bin/bash
# Read-only security audit of a macOS development workstation.
# No -e or pipefail: a probe command that fails is a finding, not a reason to stop.
set -u
# The cache and temporary files are yours only.
umask 077
# Only macOS's own tools run until sudo is dropped; the checks that don't need root get USER_PATH back (lib/runner.sh).
USER_PATH="$PATH"
PATH="${AUDIT_SYSTEM_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$ROOT_DIR/lib/system.sh"
source "$ROOT_DIR/lib/report.sh"
source "$ROOT_DIR/lib/progress.sh"
source "$ROOT_DIR/lib/runner.sh"
source "$ROOT_DIR/lib/inventory.sh"
source "$ROOT_DIR/lib/runtimes.sh"
source "$ROOT_DIR/lib/https.sh"
source "$ROOT_DIR/lib/endoflife.sh"
for check_file in "$ROOT_DIR"/checks/*.sh; do
  # shellcheck source=/dev/null
  source "$check_file"
done

SECTIONS="platform accounts network persistence secrets dev-tooling backup"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Read-only security audit of this Mac. Nothing is changed; secret values are never printed.

Options:
  --json             print a JSON report on stdout instead of the tables
  --section NAME     run only this section (repeatable): ${SECTIONS// /, }
  --verify-apps      run Gatekeeper's full check on every app (slow: hashes every file)
  --check-updates    ask Apple's servers for pending updates (about 10 s) instead of reading macOS's last check
  --refresh-cache    fetch the runtime end-of-life dates again, even if cached today
  --no-cache         fetch the runtime end-of-life dates without reading or writing the cache
  --exit-code LEVEL  exit 1 on a finding of this severity or higher: HIGH (default), MEDIUM or LOW
  -i, --interactive  browse the findings and checks in fzf after the report
  --no-color         no colour (also honours NO_COLOR)
  -h, --help         show this help

Root-only checks run when sudo has cached credentials: run 'sudo -v' first. They run first, with
macOS's own tools only; then the audit forgets the credentials (sudo -k) and runs the other checks.
Exit status: 0 no finding at the --exit-code severity or higher, 1 at least one, 2 usage error.
EOF
}

die() {
  echo "$(basename "$0"): $1" >&2
  exit 2
}

# Usage: needs_value option argument_count
needs_value() {
  [[ "$2" -ge 2 ]] || die "$1 needs a value"
}

# shellcheck disable=SC2034 # VERIFY_APPS, CHECK_UPDATES, REFRESH_CACHE and NO_CACHE are read by the checks
main() {
  local json=false selected="" color=true framed=true progress=true exit_severity=high interactive=false
  [[ -t 1 ]] || framed=false
  [[ "$framed" == true && -z "${NO_COLOR:-}" ]] || color=false
  [[ -t 2 ]] || progress=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=true; shift ;;
      --section) needs_value "$1" $#; require_section "$2"; selected="$selected $2"; shift 2 ;;
      --verify-apps) VERIFY_APPS=true; shift ;;
      --check-updates) CHECK_UPDATES=true; shift ;;
      --refresh-cache) REFRESH_CACHE=true; shift ;;
      --no-cache) NO_CACHE=true; shift ;;
      --exit-code=*) require_severity "${1#*=}"; exit_severity="$(lower_case "${1#*=}")"; shift ;;
      --exit-code) needs_value "$1" $#; require_severity "$2"; exit_severity="$(lower_case "$2")"; shift 2 ;;
      -i | --interactive) interactive=true; shift ;;
      --no-color) color=false; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  [[ "$EUID" -ne 0 ]] || die "run as your normal user, not root; root-only checks use cached sudo credentials"
  [[ "$interactive" != true || "$json" != true ]] || die "--json and --interactive don't go together"
  [[ "$interactive" != true ]] || require_browse
  # Run from /, so that no file in the current folder, such as a repo's .git/config, changes the results.
  cd / || die "cannot change to /"

  report_init "$color" "$framed"
  progress_init "$progress"
  runner_init
  trap 'progress_stop; runner_cleanup; report_cleanup' EXIT
  run_sections "${selected:-$SECTIONS}"
  if [[ "$json" == true ]]; then
    write_json_report
  else
    print_report
  fi
  [[ "$interactive" != true ]] || BROWSE_COLOR="$color" "$ROOT_DIR/lib/browse.sh" open "$RESULTS_FILE"
  ! has_findings_from "$exit_severity"
}

require_browse() {
  [[ -t 0 && -t 1 ]] || die "--interactive needs a terminal"
  PATH="$USER_PATH" has_command fzf || die "--interactive needs fzf: brew install fzf"
}

# HIGH, MEDIUM and LOW, in any case.
require_severity() {
  [[ " high medium low " == *" $(lower_case "$1") "* ]] || die "unknown --exit-code: $1 (one of: HIGH, MEDIUM, LOW)"
}

lower_case() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

require_section() {
  [[ " $SECTIONS " == *" $1 "* ]] || die "unknown section: $1 (one of: $SECTIONS)"
}

# Starts every check at once, then waits for them all.
run_sections() {
  local section
  for section in $1; do
    CHECK_SECTION="$section"
    "run_${section//-/_}_checks"
  done
  collect_results
}

main "$@"
