# mac-security-audit

[![CI](https://github.com/flombois/mac-security-audit/actions/workflows/ci.yml/badge.svg)](https://github.com/flombois/mac-security-audit/actions/workflows/ci.yml)

Read-only security audit of a macOS development workstation.

It checks the OS, accounts, network exposure, persistence, secrets at rest, developer tooling and backups.
Each check gets:

- a **status**: **RUN** (it ran without error), **SKIPPED** (it could not run here, or needs a manual review) or
  **ERROR** (it ran but could not finish, for example an output it could not read);
- for a check that ran, an **outcome**: **PASS** (no issue found) or **FAIL** (a weakness was found);
- for a failed check, a **severity**: **HIGH**, **MEDIUM** or **LOW**.

Each check has its own id, such as `network.firewall`, made of its section and name. Each check that can fail
also says why it matters: the **risk** (why the weakness is dangerous) and its **impact** (what an attacker or
an accident could do with it).

- **Read-only**: it never changes a setting, file or permission. Each finding comes with the fix to apply yourself.
  Its only write is its own cache of runtime end-of-life dates in `~/Library/Caches/mac-security-audit`.
- **No secret values**: secret findings name the file and line (`~/.zshrc:31 (GitHub token)`), never the value.
- **Same results from any folder**: it runs from `/`, so a repo's `.git/config` doesn't change them.
- Runs on the bash 3.2 and jq that ship with macOS (tested on macOS 26; aimed at macOS 27 too).

## Get started

Nothing to install: it only needs what ships with macOS, plus [fzf](https://github.com/junegunn/fzf) for `-i`.

```sh
git clone https://github.com/flombois/mac-security-audit.git
cd mac-security-audit
./audit.sh
```

Before you run it with `sudo -v`, read what runs as root: the checks queued with `run_root_check` in `checks/`.

**Limits**: a clean report doesn't mean the Mac is safe. The audit checks known weak spots in settings and
files; it is not an antivirus and doesn't look for malware already running. It audits your account only,
and doesn't scan your repositories or their dependencies.

## Usage

```sh
./audit.sh                                  # full audit
./audit.sh --section network --section secrets
./audit.sh --json | jq '.summary'            # JSON report on stdout instead of the tables
./audit.sh -i                               # browse the findings after the report
sudo -v && ./audit.sh                       # include the checks that need root
```

| Option | Effect |
|---|---|
| `--json` | Print a pretty-printed JSON report on stdout instead of the tables; the progress stays on stderr |
| `--section NAME` | Run only this section; repeatable |
| `--verify-apps` | Run Gatekeeper's full check on every app; it hashes every file, so it adds about 20 s |
| `--check-updates` | Ask Apple's servers for pending updates (`softwareupdate -l`, about 10 s) instead of reading macOS's last check |
| `--refresh-cache` | Fetch the runtime end-of-life dates again, even if the cache is less than a day old |
| `--no-cache` | Fetch the runtime end-of-life dates without reading or writing the cache |
| `-i`, `--interactive` | After the report, browse the findings and checks in [fzf](https://github.com/junegunn/fzf) (`brew install fzf`) |
| `--exit-code LEVEL` | Exit `1` on a finding of this severity or higher: `HIGH` (default), `MEDIUM` or `LOW`; `--exit-code=LEVEL` works too |
| `--no-color` | No colour; `NO_COLOR` works too |

Exit status: `0` no finding at the `--exit-code` severity or higher (`HIGH` by default), `1` at least one, `2` usage error.

Run it as your normal user: it audits your `$HOME`. Checks that need root (startup security, configuration
profiles, login items, unreadable launch daemon binaries) use `sudo -n`, so they only run when `sudo -v` cached
your credentials, and are skipped otherwise.

Cached credentials work for any program started from your terminal, so the audit guards them. The root-only
checks run first, with macOS's own tools only (`/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`). The audit then forgets
the credentials (`sudo -k`) before it starts anything else: Homebrew, Docker and its plugins, npm and the
other tools on your `PATH`. Your next `sudo` asks for your password again. This holds against programs planted
in user-writable places, such as `/opt/homebrew/bin`, but not against changes to your shell environment, as
whatever can set your `PATH` can also replace `sudo` itself.

All checks run at the same time, so a full audit takes about as long as its slowest check: about 3 s,
or 8 s with `--check-updates`; with cached credentials, the other checks wait for the root-only ones. On a
terminal, a live log shows the run across the window's width, like `docker build`: each finished check
prints a line with its result, its id and the commands it ran, and a block below lists the checks still
running, with the command each one runs and, for a slow one, its step. The block is erased at the end; the
log lines stay. It is written to stderr, so it never ends up in redirected output.

```
  PASS     platform.filevault          fdesetup status                                          1s
  FAIL     accounts.screen-lock        sysadminctl -screenLock status                           2s
[+] Auditing 6s · 87/88 done
 ⠹ platform.updates                    softwareupdate -l                                        6s
```

The commands are shown as the check wrote them, with path variables filled in. Other values stay as
`$name`, since they may hold a secret. Commands that only reshape text are left out, and so are `grep`,
`awk` and `jq` unless they read a file.

The report is printed at the end, as two tables:

1. **Checks**: every check in run order, with its status, outcome, id and detail. A skipped check gives the
   reason, or what to review yourself. The footer counts statuses and outcomes.
2. **Findings**: the failed checks, most severe first, each with its detail, its risk and the fix. The footer
   counts severities.

On a terminal, each table is framed to the window width, and long text is cut with `…`:

```
╭─ Checks (88) ───────────────────────────────────────────── my-mac · macOS 26.6.2 · 2026-10-14 16:07 ─╮
│ STATUS   OUTCOME  ID                           CHECK                    DETAIL                       │
│ ──────────────────────────────────────────────────────────────────────────────────────────────────── │
│ RUN      PASS     platform.filevault           FileVault disk encrypt…                               │
│ RUN      FAIL     network.firewall             Application firewall on  Firewall is disabled         │
│ SKIPPED           platform.startup-security    Startup security at Fu…  needs sudo: run 'sudo -v'…   │
├──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 79 run  ·  9 skipped  ·  68 pass  ·  11 fail                                                         │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭─ Findings (11) ──────────────────────────────────────────────────────────────────────────────────────╮
│ SEVERITY  ID                           CHECK                 DETAIL           RISK           FIX     │
│ ──────────────────────────────────────────────────────────────────────────────────────────────────── │
│ HIGH      network.firewall             Application firewal…  Firewall is di…  With the app…  → Syst… │
│ LOW       dev-tooling.docker-rootless  Docker daemon rootl…  the daemon run…  The Docker d…  → Use … │
├──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 3 high  ·  4 medium  ·  4 low                                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Narrow windows leave out the RISK, DETAIL and CHECK columns of the findings, in that order. Piped or
redirected (`./audit.sh | less -S`, CI logs), the tables are plain and keep the full text. `--json` also has
everything.

### Browsing the findings

With `-i`, the report is followed by a browser of the findings in fzf, most severe first. Type to filter
by id, title or detail. The finding under the cursor shows in a preview pane, beside the list from 160
columns and below it otherwise: its status, outcome and severity, the detail, why it matters, its impact,
the fix and the commands the check ran. Enter opens it in full in `less`, alt-a lists all checks, alt-f
goes back to the findings, and Esc quits. With no findings, it starts with all checks.

## Checks

| Section | What is checked |
|---|---|
| `platform` | Pending updates (from macOS's own last check, which must be under 7 days old; `--check-updates`: asks Apple's servers), automatic security responses, automatic macOS updates, FileVault, SIP, Gatekeeper, startup security (sudo), XProtect age, MDM enrollment, configuration profiles (all with sudo); apps: unsigned or ad-hoc signed (`--verify-apps`: Gatekeeper's full check); security software and other apps installed |
| `accounts` | Automatic login, guest account, screen lock delay, Touch ID for sudo, admin daily account, Find My / Activation Lock |
| `network` | Firewall, stealth mode, sharing services (SSH, SMB, AFP, Screen Sharing, Remote Management), AirPlay Receiver, listeners reachable from the network, naming common dev servers (Vite, VitePress, Angular, Next.js, Metro, Storybook…), AirDrop, Docker ports on `0.0.0.0`; remote access tools and running tunnels (ngrok, cloudflared, …); root certificates trusted by hand, warning about HTTPS proxy ones; VPNs, proxy tools and local servers installed |
| `persistence` | Third-party launch agents and daemons: missing, unsigned or script programs; enabled login items and background apps (`sfltool dumpbtm`, needs sudo): leftovers and items without a Team ID; browser extensions you installed (Chrome, Edge, Brave, Vivaldi, Arc, Firefox, Safari), warning about ones loaded from a folder; browsers and system extensions installed; manual reviews of privacy permissions and accessories |
| `secrets` | Tokens, keys and passwords in shell dotfiles, `.npmrc`, `.yarnrc`, `.yarnrc.yml`, `.bunfig.toml`, `.netrc`, `.git-credentials`; static AWS keys; Docker logins outside the Keychain; plaintext Maven passwords and Gradle properties passwords (React Native signing); static kubeconfig credentials; OpenTofu/Terraform tokens; GitHub CLI token; CLI logins (Vercel, Netlify, Firebase, Wrangler, Expo, Supabase, Fly.io, Railway, Sentry) and App Store Connect keys readable by others; `~/.ssh`, key and `~/.gnupg` permissions, keys without passphrase, weak keys, agent forwarding, `authorized_keys`; password managers installed |
| `dev-tooling` | Git credential helper and commit signing, outdated Homebrew packages and third-party taps, rootless Docker, risky container mounts, production kube contexts, Claude Code permissions and MCP servers, JetBrains trusted locations, warning when they include your home folder; VS Code, Cursor and other VS Code family editors with workspace trust off; npm, Yarn and pnpm with certificate checks off, http registries or npm install scripts on; browsers or Node started with a debugging port; language runtimes and toolchains (Java, Node, Python, Go, Rust, Ruby, C/C++), warning about end-of-life versions; JetBrains plugins (manual); package managers, IDEs and editors, editor extensions, build tools, containers and VMs, cloud CLIs, AI tools, API clients, mobile development tools and global packages (npm, pnpm, Yarn, Bun, pipx, uv, cargo, go) installed |
| `backup` | Time Machine destination and latest backup age; encryption and restore test (manual); cloud sync apps installed |

Listening sockets come from `netstat`, which shows every user's sockets without root, unlike `lsof`.

### Installed software

Each section also lists what is installed in its area. The lists come from `data/inventory.tsv`, which
finds software by app bundle id or name (in `/Applications` and `~/Applications`), by command on `PATH`,
or by path. To cover another tool, add a row there.

Frameworks and build tools installed inside projects (React, Angular, Vue, Vite, VitePress…) are not
listed: the audit doesn't scan repositories. Their global installs and CLIs are.

Runtime versions are read from version manager, Homebrew and installer folders; no runtime or compiler is
run. End-of-life dates come from the [endoflife.date API](https://endoflife.date/docs/api/v1/) (`nodejs`,
`eclipse-temurin`, `python`, `go`, `rust`, `ruby`) and are cached for 24 hours in
`~/Library/Caches/mac-security-audit/endoflife`:

- A product is fetched when its cache is missing, empty or older than 24 hours, or with `--refresh-cache`.
- A cached file is replaced only by a 2xx answer that holds release data, so an outage keeps the last good dates.
- With no cache and no answer, the check is skipped. `--no-cache` fetches into the run's temporary folder.
- Calls go through `safe_https_call` (`lib/https.sh`): HTTPS only, redirects included, TLS 1.2 or later,
  with curl's certificate, chain and host name checks, and `~/.curlrc` ignored so nothing can turn them off.

GCC and LLVM are listed without dates, because endoflife.date has none.

## JSON report

`--json` prints it on stdout, so it pipes into `jq` or a file. It lists what is installed and where secrets sit,
so keep a saved copy private: `(umask 077; mkdir -p reports; ./audit.sh --json > reports/$(date +%F).json)`;
`reports/` is gitignored. The exit status follows `--exit-code` as usual, so with `set -o pipefail`, a pipe
fails when there are findings even though the JSON is complete.

```json
{
  "host": "my-mac",
  "macos": {
    "version": "26.6.2",
    "build": "25G83"
  },
  "generatedAt": "2026-10-13T08:50:52Z",
  "summary": {
    "status": {
      "run": 79,
      "skipped": 9,
      "error": 0
    },
    "outcome": {
      "pass": 68,
      "fail": 11
    },
    "severity": {
      "high": 3,
      "medium": 4,
      "low": 4
    }
  },
  "checks": [
    {
      "id": "network.firewall",
      "section": "network",
      "title": "Application firewall on",
      "status": "run",
      "outcome": "fail",
      "severity": "high",
      "detail": "Firewall is disabled. (State = 0)",
      "risk": "With the application firewall off, every app and service listening on the network accepts connections from any network you join.",
      "impact": "On café, hotel or conference Wi-Fi, others can reach dev servers, databases, sharing services and debuggers on the Mac.",
      "remediation": "System Settings › Network › Firewall: turn on",
      "commands": [
        "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"
      ]
    }
  ]
}
```

`outcome` is `null` for a check that did not run, and `severity` is `null` unless the check failed.
`risk` and `impact` are `null` for checks that only list what is installed. `commands` lists the commands
the check ran, each once, in order.

Compare two runs:

```sh
jq -r '.checks[] | "\(.id) \(.status) \(.outcome) \(.severity)"' old.json > old.txt
jq -r '.checks[] | "\(.id) \(.status) \(.outcome) \(.severity)"' new.json | diff old.txt -
```

## Development

```sh
brew install shellcheck bats-core
shellcheck audit.sh lib/*.sh checks/*.sh
bats tests/
```

- `audit.sh` parses options and runs the sections; `lib/report.sh` records results, prints the report or the JSON;
  `lib/report.jq` builds the report's tables and `lib/table.jq` draws them (adapted from
  [github-scripts](https://github.com/flombois/github-scripts));
  `lib/runner.sh` runs the checks in parallel and collects their results in order; `lib/progress.sh` draws the live log;
  `lib/inventory.sh` finds catalogued software; `lib/runtimes.sh` finds runtime versions;
  `lib/endoflife.sh` caches end-of-life dates; `lib/https.sh` holds `safe_https_call` for verified downloads;
  `lib/system.sh` holds overridable paths and small helpers, such as `terminal_width`.
- Each `checks/NN-section.sh` defines `run_<section>_checks`, which calls `run_check "label" check_function` for
  each check. Checks run in background subshells, so a check must not rely on variables set by another.
- A check that uses sudo is queued with `run_root_check` instead; it gets only macOS's own tools on its `PATH`.
  Only those checks may use sudo: `tests/audit.bats` fails when sudo runs after `sudo -k`.
- A check reports one result, under the id its function name gives: `check_network_firewall` in section
  `network` is `network.firewall` (dev-tooling functions start with `check_dev_`). `tests/checks.bats` keeps
  ids unique and matching.
- A check function reports through `report_pass`, `report_fail` (with a severity), `report_skip`,
  `report_manual` or `report_error`. A check that ends without reporting anything is recorded as ERROR, with
  the first line it wrote to stderr. Severity: HIGH when the weakness exposes the Mac or its secrets now
  (firewall off, plaintext credentials), MEDIUM when it raises the risk, LOW for hardening.
- A check that can fail, or needs a review, has a risk and an impact in `data/risks.json`, keyed by its id.
- A DEBUG trap set by `run_check` records the commands a check runs (`record_command` in `lib/runner.sh`).
  Before a slow step, a check can call `progress_note "text"` to show that step in the live log, under its
  command.
- `lib/browse.sh` holds the `--interactive` browser; fzf runs it again for the list, preview and full view.
- Tests put stub commands first in `PATH` and `AUDIT_SYSTEM_PATH`, and use a throwaway `HOME`; see `tests/test_helper.bash`.
