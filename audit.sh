#!/usr/bin/env bash
# Read-only security audit of a macOS development workstation.
# No -e or pipefail: a probe command that fails is a finding, not a reason to stop.
set -u
ROOT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$ROOT_DIR/lib/system.sh"
source "$ROOT_DIR/lib/report.sh"
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
  --json FILE        also write a JSON report to FILE
  --section NAME     run only this section (repeatable): ${SECTIONS// /, }
  --scan-repos DIR   scan the git repositories under DIR for secrets with gitleaks
  --no-color         plain output (also honours NO_COLOR)
  -h, --help         show this help

Root-only checks run when sudo has cached credentials: run 'sudo -v' first.
Exit status: 0 no failures, 1 at least one failure, 2 usage error.
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

# shellcheck disable=SC2034 # SCAN_REPOS_DIR is read by the secrets checks
main() {
  local json_file="" selected="" color=true
  [[ -t 1 && -z "${NO_COLOR:-}" ]] || color=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) needs_value "$1" $#; json_file="$2"; shift 2 ;;
      --section) needs_value "$1" $#; require_section "$2"; selected="$selected $2"; shift 2 ;;
      --scan-repos) needs_value "$1" $#; require_dir "$2"; SCAN_REPOS_DIR="$(realpath "$2")"; shift 2 ;;
      --no-color) color=false; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  [[ "$EUID" -ne 0 ]] || die "run as your normal user, not root; root-only checks use cached sudo credentials"

  report_init "$color"
  trap report_cleanup EXIT
  run_sections "${selected:-$SECTIONS}"
  print_summary
  if [[ -n "$json_file" ]]; then
    write_json_report "$json_file"
    echo "JSON report: $json_file"
  fi
  ! has_failures
}

require_section() {
  [[ " $SECTIONS " == *" $1 "* ]] || die "unknown section: $1 (one of: $SECTIONS)"
}

require_dir() {
  [[ -d "$1" ]] || die "not a directory: $1"
}

run_sections() {
  local section
  for section in $1; do
    report_section "$section"
    "run_${section//-/_}_checks"
  done
}

main "$@"
