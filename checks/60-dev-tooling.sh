# Developer tooling: git, package managers, containers, Kubernetes, debuggers and AI coding tools.

# VS Code family: name, extensions folder under ~, settings folder under ~/Library/Application Support
VSCODE_EDITORS="Visual Studio Code	.vscode	Code
Visual Studio Code Insiders	.vscode-insiders	Code - Insiders
VSCodium	.vscode-oss	VSCodium
Cursor	.cursor	Cursor
Windsurf	.windsurf	Windsurf"
# Global package folders of pnpm, Yarn and Bun, each with a package.json listing them: "label<TAB>folder under ~"
JS_GLOBAL_FOLDERS="pnpm	~/Library/pnpm/global/*
Yarn	~/.config/yarn/global
Bun	~/.bun/install/global"
# Commands rustup puts in ~/.cargo/bin
RUSTUP_PROXIES="cargo cargo-clippy cargo-fmt cargo-miri clippy-driver rls rust-analyzer rust-gdb rust-gdbgui rust-lldb rustc rustdoc rustfmt rustup"

run_dev_tooling_checks() {
  run_check "git credential helper" check_dev_git_credentials
  run_check "git commit signing" check_dev_git_signing
  run_check "outdated Homebrew packages" check_dev_brew_outdated
  run_check "Homebrew taps" check_dev_brew_taps
  run_check "rootless Docker" check_dev_docker_rootless
  run_check "container mounts" check_dev_docker_mounts
  run_check "Kubernetes contexts" check_dev_kube_contexts
  run_check "Claude Code permissions" check_dev_claude_permissions
  run_check "Claude Code MCP servers" check_dev_claude_mcp
  run_check "JetBrains trusted locations" check_dev_ide_trusted_locations
  run_check "JetBrains plugins" check_dev_ide_plugins
  run_check "package managers" check_dev_package_managers
  run_check "IDEs and editors" check_dev_ides
  run_check "editor extensions" check_dev_editor_extensions
  run_check "VS Code workspace trust" check_dev_vscode_workspace_trust
  run_check "npm, Yarn and pnpm settings" check_dev_npm_config
  run_check "debugging ports" check_dev_debug_ports
  run_check "language runtimes" check_dev_runtimes
  run_check "runtime end of life" check_dev_runtime_support
  run_check "build tools" check_dev_build_tools
  run_check "containers and VMs" check_dev_containers_vms
  run_check "cloud and infrastructure CLIs" check_dev_cloud_cli
  run_check "AI tools" check_dev_ai_tools
  run_check "API clients" check_dev_api_clients
  run_check "mobile development tools" check_dev_mobile_dev
  run_check "global packages" check_dev_global_packages
}

check_dev_git_credentials() {
  local names helpers
  names="$(git config --get-all credential.helper 2>/dev/null | credential_helper_names)"
  helpers="$(echo "$names" | join_lines)"
  if grep -qx store <<<"$names"; then
    report_fail dev-tooling.git-credentials high "Git credentials kept in the Keychain" "credential.helper: $helpers (plaintext ~/.git-credentials)" \
      "Run: git config --global credential.helper osxkeychain, then delete ~/.git-credentials"
  else
    report_pass dev-tooling.git-credentials "Git credentials kept in the Keychain" "credential.helper: ${helpers:-none}"
  fi
}

# Prints the name of each helper on stdin, never its arguments, which may hold a token: "inline
# script" for a shell snippet (!…), otherwise the program without its folder and git-credential- prefix.
credential_helper_names() {
  local helper name
  while IFS= read -r helper; do
    case "$helper" in
      '') ;;
      '!'*) echo "inline script" ;;
      *)
        name="${helper%%[[:space:]]*}"
        name="${name##*/}"
        echo "${name#git-credential-}"
        ;;
    esac
  done
}

check_dev_git_signing() {
  if [[ "$(git config --get commit.gpgsign 2>/dev/null)" == true ]]; then
    report_pass dev-tooling.git-signing "Git commits signed" "format: $(git config --get gpg.format 2>/dev/null || echo openpgp)"
  else
    report_fail dev-tooling.git-signing low "Git commits signed" "commit.gpgsign is off" \
      "git config --global gpg.format ssh; git config --global user.signingkey ~/.ssh/id_ed25519.pub; git config --global commit.gpgsign true"
  fi
}

check_dev_brew_outdated() {
  if ! has_command brew; then
    report_skip dev-tooling.brew-outdated "Homebrew packages up to date" "Homebrew not installed"
    return
  fi
  local outdated
  outdated="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet 2>/dev/null | join_lines)"
  if [[ -z "$outdated" ]]; then
    report_pass dev-tooling.brew-outdated "Homebrew packages up to date" "against the last 'brew update'"
  else
    report_fail dev-tooling.brew-outdated low "Homebrew packages up to date" "$outdated" \
      "Run: brew update && brew upgrade"
  fi
}

check_dev_brew_taps() {
  if ! has_command brew; then
    report_skip dev-tooling.brew-taps "Third-party Homebrew taps" "Homebrew not installed"
    return
  fi
  local taps
  taps="$(brew tap 2>/dev/null | grep -v '^homebrew/' | join_lines)"
  report_pass dev-tooling.brew-taps "Third-party Homebrew taps" "${taps:-none}"
}

check_dev_docker_rootless() {
  if ! docker_running; then
    report_skip dev-tooling.docker-rootless "Docker daemon rootless" "Docker is not running"
    return
  fi
  if docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless; then
    report_pass dev-tooling.docker-rootless "Docker daemon rootless"
  else
    report_fail dev-tooling.docker-rootless low "Docker daemon rootless" "the daemon runs as root inside its VM" \
      "Use rootless mode (Colima, Podman or Docker rootless) to limit what a container escape reaches"
  fi
}

check_dev_docker_mounts() {
  if ! docker_running; then
    report_skip dev-tooling.docker-mounts "Containers don't mount your home or the Docker socket" "Docker is not running"
    return
  fi
  local containers
  containers="$(docker ps -q 2>/dev/null | xargs docker inspect --format '{{.Name}}{{range .Mounts}} {{.Source}}{{end}}' 2>/dev/null \
    | awk -v home="$HOME" '{
        for (i = 2; i <= NF; i++)
          if ($i == home || $i == "/" || $i == "/Users" || $i ~ /docker\.sock$/) { sub(/^\//, "", $1); print $1; break }
      }' | join_lines)"
  if [[ -z "$containers" ]]; then
    report_pass dev-tooling.docker-mounts "Containers don't mount your home or the Docker socket"
  else
    report_fail dev-tooling.docker-mounts medium "Containers don't mount your home or the Docker socket" "$containers" \
      "Mount only the project folder; avoid exposing docker.sock to containers"
  fi
}

check_dev_kube_contexts() {
  if ! has_command kubectl; then
    report_skip dev-tooling.kube-contexts "No production Kubernetes contexts" "kubectl not installed"
    return
  fi
  local contexts
  contexts="$(kubectl config get-contexts -o name 2>/dev/null | grep -i prod | join_lines)"
  if [[ -z "$contexts" ]]; then
    report_pass dev-tooling.kube-contexts "No production Kubernetes contexts"
  else
    report_fail dev-tooling.kube-contexts low "No production Kubernetes contexts" "$contexts" \
      "Remove production contexts, or keep them in a separate KUBECONFIG with short-lived, read-only credentials"
  fi
}

check_dev_claude_permissions() {
  local file="$HOME/.claude/settings.json" risks
  if [[ ! -f "$file" ]]; then
    report_skip dev-tooling.claude-permissions "Claude Code asks before risky actions" "no ~/.claude/settings.json"
    return
  fi
  risks="$(jq -r '[
      (if .permissions.defaultMode == "bypassPermissions" then "defaultMode is bypassPermissions" else empty end),
      (if .skipDangerousModePermissionPrompt == true then "bypass mode prompt skipped" else empty end),
      (.permissions.allow // [] | .[] | select(. == "Bash" or . == "Bash(*)" or . == "Bash(*:*)") | "allows \(.)")
    ] | join(", ")' "$file" 2>/dev/null)"
  if [[ -z "$risks" ]]; then
    report_pass dev-tooling.claude-permissions "Claude Code asks before risky actions"
  else
    report_fail dev-tooling.claude-permissions medium "Claude Code asks before risky actions" "$risks" \
      "Allow specific commands only (e.g. Bash(git status)); turn on the sandbox with /sandbox"
  fi
}

check_dev_claude_mcp() {
  local file="$HOME/.claude.json" servers
  if [[ ! -f "$file" ]]; then
    report_skip dev-tooling.claude-mcp "Claude Code MCP servers" "no ~/.claude.json"
    return
  fi
  servers="$(jq -r '(.mcpServers // {}) | keys | join(", ")' "$file" 2>/dev/null)"
  report_pass dev-tooling.claude-mcp "Claude Code MCP servers" \
    "user-level: ${servers:-none}; run /mcp in Claude Code to also see claude.ai connectors and project servers"
}

check_dev_ide_trusted_locations() {
  local settings_dirs broad
  settings_dirs="$(jetbrains_settings_dirs)"
  if [[ -z "$settings_dirs" ]]; then
    report_skip dev-tooling.ide-trusted-locations "JetBrains trusted locations" "no JetBrains IDE settings found"
    return
  fi
  broad="$(echo "$settings_dirs" | per_ide jetbrains_broad_locations)"
  if [[ -n "$broad" ]]; then
    report_fail dev-tooling.ide-trusted-locations medium "JetBrains trusts only project folders" "$broad" \
      "Settings › Build, Execution, Deployment › Trusted Locations: remove it, so projects you clone ask before running their build scripts"
  else
    report_pass dev-tooling.ide-trusted-locations "JetBrains trusted locations" \
      "$(echo "$settings_dirs" | per_ide jetbrains_trusted_locations)"
  fi
}

# The plugins folder mixes plugins you chose with updated bundled ones, so this stays manual.
check_dev_ide_plugins() {
  report_manual dev-tooling.ide-plugins "Review JetBrains plugins" \
    "Settings › Plugins › Installed: remove plugins you don't use"
}

# Prints the settings folder of the newest version of each JetBrains IDE.
jetbrains_settings_dirs() {
  local dir
  for dir in "$HOME/Library/Application Support/JetBrains"/*20[0-9][0-9].[0-9]*; do
    [[ -d "$dir" ]] && echo "$dir"
  done | awk '{ ide = $0; sub(/[0-9]+\.[0-9]+$/, "", ide); newest[ide] = $0 } END { for (ide in newest) print newest[ide] }' | sort
}

# Usage: per_ide function, with settings folders on stdin
# Prints "IDE: items; IDE: items", skipping IDEs for which the function prints nothing.
per_ide() {
  local dir items
  while IFS= read -r dir; do
    items="$("$1" "$dir" | join_lines)"
    [[ -z "$items" ]] || echo "$(basename "$dir"): $items"
  done | join_groups
}

# Prints the trusted locations, with ~ for the home folder; "none" when there are none.
jetbrains_trusted_locations() {
  local locations
  # shellcheck disable=SC2016 # $USER_HOME$ is JetBrains' placeholder, not a variable
  locations="$(sed -n '/name="TRUSTED_PATHS"/,/<\/list>/s/.*<option value="\([^"]*\)".*/\1/p' \
    "$1/options/trusted-paths.xml" 2>/dev/null | sed 's#^\$USER_HOME\$#~#')"
  echo "${locations:-none}"
}

# Prints the trusted locations that hold your home folder.
jetbrains_broad_locations() {
  jetbrains_trusted_locations "$1" | while IFS= read -r location; do
    case "$location" in
      "~" | "~/" | / | /Users | /Users/ | "$HOME" | "$HOME/") echo "$location" ;;
    esac
  done
}

check_dev_package_managers() {
  report_catalogue dev-tooling.package-managers "Package and version managers" package-managers
}

check_dev_ides() {
  report_catalogue dev-tooling.ides "IDEs and editors" ides
}

check_dev_build_tools() {
  report_catalogue dev-tooling.build-tools "Build tools" build-tools
}

check_dev_containers_vms() {
  report_catalogue dev-tooling.containers-vms "Containers and VMs" containers-vms
}

check_dev_cloud_cli() {
  report_catalogue dev-tooling.cloud-cli "Cloud and infrastructure CLIs" cloud-cli
}

check_dev_ai_tools() {
  report_catalogue dev-tooling.ai-tools "AI tools" ai-tools
}

check_dev_api_clients() {
  report_catalogue dev-tooling.api-clients "API clients" api-clients
}

check_dev_mobile_dev() {
  report_catalogue dev-tooling.mobile-dev "Mobile development tools" mobile-dev
}

check_dev_editor_extensions() {
  local editor folder _settings extensions
  extensions="$(echo "$VSCODE_EDITORS" | while IFS=$'\t' read -r editor folder _settings; do
    editor_extensions "$HOME/$folder/extensions" | label_items "$editor"
  done | join_groups)"
  report_pass dev-tooling.editor-extensions "Editor extensions" "${extensions:-none found}"
}

# Prints the extension ids of a VS Code family extensions folder.
editor_extensions() {
  [[ -d "$1" ]] || return 0
  if [[ -e "$1/extensions.json" ]]; then
    jq -r '.[]?.identifier.id // empty' "$1/extensions.json" 2>/dev/null | sort -fu
  else
    find "$1" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sed -E 's/-[0-9]+\..*$//' | sort -fu
  fi
}

check_dev_global_packages() {
  local packages
  packages="$({
    global_npm_packages | label_items npm
    js_global_packages
    has_command pipx && pipx list --short 2>/dev/null | awk '{ print $1 }' | label_items pipx
    has_command uv && uv tool list 2>/dev/null | awk '/^[^ -]/ && $2 ~ /^v/ { print $1 }' | label_items uv
    cargo_installs | label_items cargo
    folder_entries "$HOME/go/bin" | label_items go
  } | join_groups)"
  report_pass dev-tooling.global-packages "Globally installed packages" "${packages:-none found}"
}

global_npm_packages() {
  has_command npm || return 0
  npm ls -g --depth=0 --json 2>/dev/null |
    jq -r '.dependencies // {} | keys[] | select(. != "npm" and . != "corepack")' 2>/dev/null
}

# Prints "label: a, b" for pnpm, Yarn and Bun, from their global package.json; none of them is run.
js_global_packages() {
  local label folder package_json
  echo "$JS_GLOBAL_FOLDERS" | while IFS=$'\t' read -r label folder; do
    # shellcheck disable=SC2045,SC2046 # the pnpm folder is a glob
    for package_json in $(expand_tilde "$folder")/package.json; do
      [[ -f "$package_json" ]] || continue
      jq -r '.dependencies // {} | keys[]' "$package_json" 2>/dev/null
    done | sort -u | label_items "$label"
  done
}

cargo_installs() {
  folder_entries "$HOME/.cargo/bin" | while IFS= read -r command; do
    [[ " $RUSTUP_PROXIES " == *" $command "* ]] || echo "$command"
  done
}

# Prints the names in a folder, if it exists.
folder_entries() {
  [[ -d "$1" ]] || return 0
  find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -exec basename {} \; | sort
}

check_dev_runtimes() {
  local runtimes
  runtimes="$(installed_runtimes | runtimes_by_language)"
  report_pass dev-tooling.runtimes "Language runtimes and toolchains" "${runtimes:-none found}"
}

# Prints "Java: 21.0.2 (SDKMAN), 17.0.9 (Homebrew); Node: …" from installed_runtimes lines.
runtimes_by_language() {
  awk -F'\t' '
    !($1 in versions) { order[++count] = $1 }
    { entry = $2 " (" $3 ")"; versions[$1] = ($1 in versions) ? versions[$1] ", " entry : entry }
    END { for (i = 1; i <= count; i++) printf "%s%s: %s", (i > 1 ? "; " : ""), order[i], versions[order[i]] }'
}

check_dev_runtime_support() {
  local ended dates
  progress_note "endoflife.date"
  prepare_eol_cache
  refresh_eol_cache
  if ! has_eol_data; then
    report_skip dev-tooling.runtime-support "Runtimes still get security fixes" \
      "endoflife.date unreachable and nothing cached; retry online"
    return
  fi
  dates="dates from endoflife.date, fetched $(eol_data_date)"
  ended="$(installed_runtimes | ended_runtimes | join_lines)"
  if [[ -n "$ended" ]]; then
    report_fail dev-tooling.runtime-support medium "Runtimes still get security fixes" "end of life: $ended ($dates)" \
      "Remove the versions you no longer use and move projects to supported ones; for Rust, run rustup update"
  else
    report_pass dev-tooling.runtime-support "Runtimes still get security fixes" "$dates"
  fi
}

# Prints "Node 20.11.1 (nvm, since 2026-04-30)" for each runtime past its end of life.
ended_runtimes() {
  local today runtime version source eol
  today="$(date +%F)"
  while IFS=$'\t' read -r runtime version source; do
    eol="$(end_of_life "$runtime" "$version")"
    [[ -z "$eol" || "$eol" > "$today" ]] || echo "$runtime $version ($source, since $eol)"
  done
}

check_dev_vscode_workspace_trust() {
  local editors untrusting
  editors="$(vscode_settings_files)"
  if [[ -z "$editors" ]]; then
    report_skip dev-tooling.vscode-workspace-trust "VS Code workspace trust on" "no VS Code family editor found"
    return
  fi
  untrusting="$(echo "$editors" | while IFS=$'\t' read -r editor settings; do
    ! workspace_trust_off "$settings" || echo "$editor"
  done | join_lines)"
  if [[ -n "$untrusting" ]]; then
    report_fail dev-tooling.vscode-workspace-trust medium "VS Code workspace trust on" "turned off in $untrusting" \
      "Remove \"security.workspace.trust.enabled\": false from settings.json, so folders you open ask before running tasks and extensions"
  else
    report_pass dev-tooling.vscode-workspace-trust "VS Code workspace trust on"
  fi
}

# Prints "editor<TAB>settings.json path" for each installed VS Code family editor.
vscode_settings_files() {
  local editor _extensions folder
  echo "$VSCODE_EDITORS" | while IFS=$'\t' read -r editor _extensions folder; do
    folder="$HOME/Library/Application Support/$folder"
    [[ ! -d "$folder" ]] || printf '%s\t%s\n' "$editor" "$folder/User/settings.json"
  done
}

# settings.json may hold comments, so it is matched line by line instead of parsed; // lines don't count.
workspace_trust_off() {
  grep -Eq '^[^/]*"security\.workspace\.trust\.enabled"[[:space:]]*:[[:space:]]*false' "$1" 2>/dev/null
}

check_dev_npm_config() {
  if ! has_command npm && ! has_command yarn && ! has_command pnpm && ! has_command bun; then
    report_skip dev-tooling.npm-config "npm, Yarn and pnpm check TLS and skip install scripts" "no JavaScript package manager found"
    return
  fi
  local unsafe_tls scripts=""
  unsafe_tls="$(js_unsafe_tls_settings | join_lines)"
  ! npm_runs_install_scripts || scripts="npm runs install scripts (ignore-scripts not set)"
  if [[ -n "$unsafe_tls" ]]; then
    report_fail dev-tooling.npm-config medium "npm, Yarn and pnpm check TLS and skip install scripts" \
      "$unsafe_tls${scripts:+, $scripts}" \
      "Remove these settings and use https registries; for a company CA, set cafile (npm, pnpm) or caFilePath (Yarn) instead"
  elif [[ -n "$scripts" ]]; then
    report_fail dev-tooling.npm-config low "npm, Yarn and pnpm check TLS and skip install scripts" "$scripts" \
      "Run: npm config set ignore-scripts true; in a project that needs them, add ignore-scripts=false to its .npmrc"
  else
    report_pass dev-tooling.npm-config "npm, Yarn and pnpm check TLS and skip install scripts"
  fi
}

# Prints "setting in ~/file" for each setting that turns off certificate checks or uses an http registry.
js_unsafe_tls_settings() {
  local npmrc="${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
  unsafe_settings "$npmrc" strict-ssl=false '^[[:space:]]*strict-ssl[[:space:]]*=[[:space:]]*false'
  unsafe_settings "$npmrc" "http registry" '^[^#;]*registry[[:space:]]*=[[:space:]]*"?http://'
  unsafe_settings "$HOME/Library/Preferences/pnpm/rc" strict-ssl=false '^[[:space:]]*strict-ssl[[:space:]]*=[[:space:]]*false'
  unsafe_settings "$HOME/Library/Preferences/pnpm/rc" "http registry" '^[^#;]*registry[[:space:]]*=[[:space:]]*"?http://'
  unsafe_settings "$HOME/.yarnrc.yml" "enableStrictSsl: false" '^[[:space:]]*enableStrictSsl:[[:space:]]*false'
  unsafe_settings "$HOME/.yarnrc.yml" "http registry" '^[^#]*npmRegistryServer:[[:space:]]*["'"'"']?http://'
  unsafe_settings "$HOME/.yarnrc" "strict-ssl false" '^[[:space:]]*"?strict-ssl"?[[:space:]]+false'
  unsafe_settings "$HOME/.yarnrc" "http registry" '^[^#]*registry"?[[:space:]]+"?http://'
  unsafe_settings "$HOME/.bunfig.toml" "http registry" '^[^#]*registry[[:space:]]*=[[:space:]]*.*"http://'
}

# Usage: unsafe_settings file label regex; prints "label in ~/file" when a line matches.
unsafe_settings() {
  ! grep -qE -- "$3" "$1" 2>/dev/null || echo "$2 in $(tilde_path "$1")"
}

# npm reads ignore-scripts from its user config and from the environment; pnpm 10 and Bun skip
# dependencies' scripts by default.
npm_runs_install_scripts() {
  has_command npm || return 1
  [[ "${npm_config_ignore_scripts:-${NPM_CONFIG_IGNORE_SCRIPTS:-}}" != true ]] || return 1
  ! grep -qE '^[[:space:]]*ignore-scripts[[:space:]]*=[[:space:]]*true' "${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}" 2>/dev/null
}

check_dev_debug_ports() {
  local debuggers
  debuggers="$(debugging_processes)"
  if [[ -z "$debuggers" ]]; then
    report_pass dev-tooling.debug-ports "No browser or Node debugger open"
  elif echo "$debuggers" | grep -q remote-debugging; then
    report_fail dev-tooling.debug-ports medium "No browser or Node debugger open" "$(echo "$debuggers" | join_lines)" \
      "Quit the browser and start it normally; infostealers start browsers this way to read their cookies"
  else
    report_fail dev-tooling.debug-ports low "No browser or Node debugger open" "$(echo "$debuggers" | join_lines)" \
      "Stop the debugging session when you are done"
  fi
}

# Prints "program flag" for each running process started with a debugging flag. Only the flag is
# kept, since the other arguments may hold secrets. The brackets keep this awk from matching itself.
debugging_processes() {
  ps -axww -o pid=,args= 2>/dev/null | awk '
    match($0, / --(remote-debugging-por[t]|inspec[t](-brk|-wait)?)(=[^[:space:]]*)?( |$)/) {
      flag = substr($0, RSTART + 1, RLENGTH - 1); sub(/ $/, "", flag)
      print $1 "\t" flag
    }' | while IFS=$'\t' read -r pid flag; do
    echo "$(basename "$(ps -o comm= -p "$pid" 2>/dev/null || echo unknown)") $flag"
  done | sort -u
}
