# mac-security-audit

Read-only security audit of a macOS development workstation.

It checks the OS, accounts, network exposure, persistence, secrets at rest, developer tooling and backups,
and reports each check as **PASS**, **WARN**, **FAIL**, **INFO**, **SKIP** or **MANUAL**.

- **Read-only**: it never changes a setting, file or permission. Each finding comes with the fix to apply yourself.
- **No secret values**: secret findings name the file and line (`~/.zshrc:31 (GitHub token)`), never the value.
- Runs on the bash 3.2 and jq that ship with macOS (tested on macOS 26; aimed at macOS 27 too).

## Usage

```sh
./audit.sh                                  # full audit
./audit.sh --section network --section secrets
./audit.sh --json reports/$(date +%F).json   # also write a JSON report
./audit.sh --scan-repos ~/repositories      # also scan git history with gitleaks
sudo -v && ./audit.sh                       # include the checks that need root
```

| Option | Effect |
|---|---|
| `--json FILE` | Also write a pretty-printed JSON report |
| `--section NAME` | Run only this section; repeatable |
| `--scan-repos DIR` | Scan every git repository under `DIR` with [gitleaks](https://github.com/gitleaks/gitleaks) (`--redact`) |
| `--no-color` | Plain output; `NO_COLOR` works too |

Exit status: `0` no failures, `1` at least one failure, `2` usage error.

Run it as your normal user: it audits your `$HOME`. Checks that need root (startup security, unreadable
launch daemon binaries) use `sudo -n`, so they only run when `sudo -v` cached your credentials, and are
skipped otherwise. `softwareupdate -l` makes the platform section take about 30 seconds.

## Checks

| Section | What is checked |
|---|---|
| `platform` | Pending updates, automatic security responses, automatic macOS updates, FileVault, SIP, Gatekeeper, startup security (sudo), XProtect age, MDM enrollment |
| `accounts` | Automatic login, guest account, screen lock delay, Touch ID for sudo, admin daily account, Find My / Activation Lock |
| `network` | Firewall, stealth mode, sharing services (SSH, SMB, AFP, Screen Sharing, Remote Management), AirPlay Receiver, listeners reachable from the network, AirDrop, Docker ports on `0.0.0.0` |
| `persistence` | Third-party launch agents and daemons: missing, unsigned or script programs; manual reviews of login items, privacy permissions, accessories and browser extensions |
| `secrets` | Tokens, keys and passwords in shell dotfiles, `.npmrc`, `.netrc`, `.git-credentials`; static AWS keys; Docker logins outside the Keychain; plaintext Maven passwords; static kubeconfig credentials; OpenTofu/Terraform tokens; GitHub CLI token; gitleaks scan of repositories (opt-in) |
| `dev-tooling` | `~/.ssh`, key and `~/.gnupg` permissions, keys without passphrase, weak keys, agent forwarding, `authorized_keys`, git credential helper and commit signing, outdated Homebrew packages and third-party taps, rootless Docker, risky container mounts, production kube contexts, Claude Code permissions and MCP servers, JetBrains trusted locations (manual) |
| `backup` | Time Machine destination and latest backup age; encryption and restore test (manual) |

Listening sockets come from `netstat`, which shows every user's sockets without root, unlike `lsof`.

## JSON report

```json
{
  "host": "my-mac",
  "macos": {
    "version": "26.6.2",
    "build": "25G83"
  },
  "generatedAt": "2026-10-13T08:50:52Z",
  "summary": {
    "pass": 21,
    "warn": 7,
    "fail": 3,
    "info": 1,
    "skip": 3,
    "manual": 6
  },
  "checks": [
    {
      "id": "platform.filevault",
      "section": "platform",
      "status": "pass",
      "title": "FileVault disk encryption on",
      "detail": "",
      "remediation": ""
    }
  ]
}
```

Compare two runs:

```sh
jq -r '.checks[] | "\(.id) \(.status)"' old.json > old.txt
jq -r '.checks[] | "\(.id) \(.status)"' new.json | diff old.txt -
```

## Development

```sh
brew install shellcheck bats-core
shellcheck audit.sh lib/*.sh checks/*.sh
bats tests/
```

- `audit.sh` parses options and runs the sections; `lib/report.sh` records and prints results and writes JSON;
  `lib/system.sh` holds overridable paths and small helpers.
- Each `checks/NN-section.sh` defines `run_<section>_checks` and one `check_*` function per check, which reports
  through `report_pass`, `report_warn`, `report_fail`, `report_info`, `report_skip` or `report_manual`.
- Tests put stub commands first in `PATH` and use a throwaway `HOME`; see `tests/test_helper.bash`.
