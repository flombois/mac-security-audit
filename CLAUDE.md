# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Read-only macOS security audit for developer Macs, written in bash + jq. User-facing behaviour, options and
the JSON schema are documented in README.md; keep README in sync when changing checks, options or output.

## Commands

```sh
brew install shellcheck bats-core           # dev tools (same as CI)
shellcheck audit.sh lib/*.sh checks/*.sh    # lint (config: .shellcheckrc)
bats tests/                                 # all tests
bats tests/network.bats                     # one file
bats tests/network.bats -f 'firewall off'   # one test, by name regex
./audit.sh --section network --no-color     # run one section for real
./audit.sh --json | jq '.summary'
```

CI (`.github/workflows/ci.yml`, macos-latest) runs lint, tests, then a smoke `./audit.sh --json` that must
exit 0 or 1 and produce checks.

## Hard constraints

- **Read-only**: never change a setting, file or permission on the Mac. The only write allowed is the
  end-of-life cache in `~/Library/Caches/mac-security-audit`. Findings carry a remediation for the user to apply.
- **Never print secret values**: secret findings name file and line (`~/.zshrc:31 (GitHub token)`) only.
- **bash 3.2 and the system jq**: only what ships with macOS (no associative arrays, `mapfile`, `${x,,}`, etc.).
  fzf is the only optional extra, for `-i`.
- Network calls go through `safe_https_call` (`lib/https.sh`) only.

## Architecture

- `audit.sh` sets `PATH` to macOS's own tools (`AUDIT_SYSTEM_PATH`), keeps the user's in `USER_PATH`, sources
  every `lib/*.sh` and `checks/*.sh`, `cd /`, then calls `run_<section>_checks` for each section in
  `SECTIONS`, then `collect_results` and prints the report or JSON. Adding a section means a new
  `checks/NN-name.sh` **and** adding it to `SECTIONS`.
- `lib/runner.sh`: `run_check "label" fn` starts each check in a **background subshell** (all run in
  parallel), with its own `RESULTS_FILE` (`$RUNNER_DIR/n.ndjson`). Checks therefore must not rely on globals set
  by other checks. A DEBUG trap (`record_command`) records the commands each check runs for the report.
- **sudo guard**: checks using sudo are queued with `run_root_check` and get only system tools on `PATH`. They run
  first; then sudo is dropped (`sudo -k`) and user checks start with `USER_PATH`. Only root checks may call
  sudo — `tests/audit.bats` fails if sudo runs after `sudo -k`. Use `sudo -n`, never prompt.
- `lib/report.sh`: results are NDJSON lines; `lib/report.jq` builds the tables, `lib/table.jq` draws them,
  `lib/text.jq` keeps text printable. `lib/progress.sh` draws the live log on stderr; `lib/browse.sh` is the
  fzf browser (re-invoked by fzf itself).
- `lib/system.sh` holds env-overridable paths (e.g. `SOCKETFILTERFW`, `INVENTORY_APP_DIRS`) and helpers
  (`join_lines`, `label_items`, `tilde_path`, `file_mode`, `days_since`, …) — reuse them.
- `lib/inventory.sh` + `data/inventory.tsv`: "installed software" listings (`report_catalogue id title category`);
  add a TSV row to cover a new tool. `lib/runtimes.sh` reads runtime versions from folders (never runs them);
  `lib/endoflife.sh` caches endoflife.date data.

## Writing a check

- Function `check_<section>_<name>` registered in `run_<section>_checks`; its id is `<section>.<name-with-dashes>`
  (dev-tooling functions start with `check_dev_`). A check reports exactly one result, under that id;
  `tests/checks.bats` enforces unique, matching ids.
- Report with `report_pass id title [detail]`, `report_fail id high|medium|low title detail remediation`,
  `report_skip id title reason`, `report_manual id title instructions`, `report_error id title detail`.
  A check that reports nothing is recorded as ERROR.
- Severity: HIGH = exposes the Mac or its secrets now; MEDIUM = raises the risk; LOW = hardening.
- Every check that can fail or needs a manual review needs a `risk` and `impact` entry in `data/risks.json`
  keyed by id (enforced by `tests/checks.bats`).
- Call external tools via overridable path variables from `lib/system.sh` where one exists, so tests can stub them.
- Before a slow step, `progress_note "text"` shows it in the live log.

## Tests

`tests/<section>.bats` with `load test_helper` and `setup_audit checks/NN-section.sh` in `setup`. The helper puts
a stub dir first in `PATH` and `AUDIT_SYSTEM_PATH`, uses a throwaway `HOME`/`TMPDIR`, and stubs sudo as
unavailable. Vocabulary: `stub_command name output [status]`, `stub_script name <<'EOF'`, `given_app`,
`given_cached_sudo`, `result_of id` (→ `pass`, `fail <severity>`, `skipped`, `error`), `detail_of id`,
`days_ago N`. Real command outputs live in `tests/fixtures/`. Pattern: stub → `run check_fn` → assert `result_of`.
