#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/60-dev-tooling.sh
  stub_command pkgutil "No receipt for 'com.apple.pkg.CLTools_Executables' found at '/'." 1
  given_api_answer 500 '{}'
  given_eol_cache nodejs 18=2000-01-01 26=2999-01-01
  given_eol_cache eclipse-temurin 8=2000-01-01
  given_eol_cache ruby 2.0.0=2016-02-24
}

# Usage: given_eol_cache product cycle=date...; writes a cache file fetched just now.
given_eol_cache() {
  local product="$1"
  shift
  mkdir -p "$EOL_CACHE_DIR"
  eol_releases "$@" >"$EOL_CACHE_DIR/$product.json"
}

# Usage: eol_releases cycle=date...; prints an endoflife.date answer, an empty date meaning none yet.
eol_releases() {
  printf '%s\n' "$@" | jq -R 'split("=") | {name: .[0], eolFrom: (if .[1] == "" then null else .[1] end)}' |
    jq -s '{schema_version: "1.2.1", result: {releases: .}}'
}

# Usage: given_api_answer http_status body; curl records its arguments and answers so.
given_api_answer() {
  printf '%s' "$2" >"$STUB_DIR/curl.body"
  stub_script curl <<STUB
echo "\$*" >>"$STUB_DIR/curl.calls"
while [[ \$# -gt 0 ]]; do
  [[ "\$1" != --output ]] || cp "$STUB_DIR/curl.body" "\$2"
  shift
done
printf '%s' "$1"
STUB
}

# Makes every cache file older than a day.
given_outdated_cache() {
  touch -t 202001010000 "$EOL_CACHE_DIR"/*.json
}

curl_calls() {
  [[ ! -e "$STUB_DIR/curl.calls" ]] || cat "$STUB_DIR/curl.calls"
}

# Usage: given_folder path_under_home_or_absolute
given_folder() {
  mkdir -p "$1"
}

# Usage: given_jdk folder java_version
given_jdk() {
  mkdir -p "$1"
  echo "JAVA_VERSION=\"$2\"" >"$1/release"
}

@test "plaintext git credential store fails" {
  git config --global credential.helper store

  run check_dev_git_credentials

  [[ "$(result_of dev-tooling.git-credentials)" == "fail high" ]]
}

@test "Keychain git credential helper passes" {
  git config --global credential.helper osxkeychain

  run check_dev_git_credentials

  [[ "$(result_of dev-tooling.git-credentials)" == pass ]]
}

@test "a git credential store with its own file fails" {
  git config --global credential.helper "store --file=$HOME/.my-credentials"

  run check_dev_git_credentials

  [[ "$(result_of dev-tooling.git-credentials)" == "fail high" ]]
}

@test "git credential helpers are shown by name, without their arguments" {
  git config --global credential.helper "cache --timeout=3600"
  git config --global --add credential.helper /usr/local/bin/git-credential-manager

  run check_dev_git_credentials

  [[ "$(detail_of dev-tooling.git-credentials)" == "credential.helper: cache, manager" ]]
}

@test "an inline git credential script is not printed" {
  git config --global credential.helper '!f() { echo password=ghp_secret; }; f'

  run check_dev_git_credentials

  [[ "$(detail_of dev-tooling.git-credentials)" == "credential.helper: inline script" ]]
}

@test "an inline git credential script that mentions store passes" {
  git config --global credential.helper '!f() { echo "username=store"; }; f'

  run check_dev_git_credentials

  [[ "$(result_of dev-tooling.git-credentials)" == pass ]]
}

@test "no git credential helper says none" {
  run check_dev_git_credentials

  [[ "$(detail_of dev-tooling.git-credentials)" == "credential.helper: none" ]]
}

@test "unsigned commits warn" {
  run check_dev_git_signing

  [[ "$(result_of dev-tooling.git-signing)" == "fail low" ]]
}

@test "SSH signed commits pass" {
  git config --global commit.gpgsign true
  git config --global gpg.format ssh

  run check_dev_git_signing

  [[ "$(detail_of dev-tooling.git-signing)" == "format: ssh" ]]
}

@test "outdated Homebrew packages warn and are named" {
  stub_command brew $'jq\nwget'

  run check_dev_brew_outdated

  [[ "$(detail_of dev-tooling.brew-outdated)" == "jq, wget" ]]
}

@test "third-party Homebrew taps are listed" {
  stub_command brew $'homebrew/core\nsdkman/tap'

  run check_dev_brew_taps

  [[ "$(detail_of dev-tooling.brew-taps)" == "sdkman/tap" ]]
}

@test "rootless Docker passes" {
  stub_script docker <<'EOF'
[[ "$1" == info && "$*" == *SecurityOptions* ]] && echo '["name=seccomp,profile=builtin","name=rootless"]'
exit 0
EOF

  run check_dev_docker_rootless

  [[ "$(result_of dev-tooling.docker-rootless)" == pass ]]
}

@test "rootful Docker warns" {
  stub_script docker <<'EOF'
[[ "$1" == info && "$*" == *SecurityOptions* ]] && echo '["name=seccomp,profile=builtin","name=cgroupns"]'
exit 0
EOF

  run check_dev_docker_rootless

  [[ "$(result_of dev-tooling.docker-rootless)" == "fail low" ]]
}

@test "container mounting home or the Docker socket warns" {
  stub_script docker <<EOF
case "\$1" in
  ps) echo abc ;;
  inspect) printf '/web /tmp/project\n/everything $HOME\n/ci /var/run/docker.sock\n' ;;
esac
exit 0
EOF

  run check_dev_docker_mounts

  [[ "$(detail_of dev-tooling.docker-mounts)" == "everything, ci" ]]
}

@test "production Kubernetes context warns" {
  stub_command kubectl $'kind-dev\nprod-eu-admin'

  run check_dev_kube_contexts

  [[ "$(detail_of dev-tooling.kube-contexts)" == "prod-eu-admin" ]]
}

@test "Claude Code bypassing permissions warns" {
  mkdir -p "$HOME/.claude"
  echo '{"permissions": {"defaultMode": "bypassPermissions", "allow": ["Bash(*)"]}}' >"$HOME/.claude/settings.json"

  run check_dev_claude_permissions

  [[ "$(detail_of dev-tooling.claude-permissions)" == "defaultMode is bypassPermissions, allows Bash(*)" ]]
}

@test "Claude Code with specific allow rules passes" {
  mkdir -p "$HOME/.claude"
  echo '{"permissions": {"allow": ["Bash(git status)"]}}' >"$HOME/.claude/settings.json"

  run check_dev_claude_permissions

  [[ "$(result_of dev-tooling.claude-permissions)" == pass ]]
}

@test "Claude Code MCP servers are listed" {
  echo '{"mcpServers": {"github": {}, "idea": {}}}' >"$HOME/.claude.json"

  run check_dev_claude_mcp

  [[ "$(detail_of dev-tooling.claude-mcp)" == "user-level: github, idea;"* ]]
}

# Usage: given_jetbrains_trusted_locations ide_folder location...
given_jetbrains_trusted_locations() {
  local options_dir="$HOME/Library/Application Support/JetBrains/$1/options" location
  shift
  mkdir -p "$options_dir"
  {
    echo '<application>'
    echo '  <component name="Trusted.Paths.Settings">'
    echo '    <option name="TRUSTED_PATHS">'
    echo '      <list>'
    for location in "$@"; do
      echo "        <option value=\"$location\" />"
    done
    echo '      </list>'
    echo '    </option>'
    echo '  </component>'
    echo '</application>'
  } >"$options_dir/trusted-paths.xml"
}

@test "JetBrains trusted locations are listed with ~" {
  given_jetbrains_trusted_locations IntelliJIdea2026.2 '$USER_HOME$/repositories/github.com/flombois' '/opt/work'

  run check_dev_ide_trusted_locations

  [[ "$(detail_of dev-tooling.ide-trusted-locations)" == "IntelliJIdea2026.2: ~/repositories/github.com/flombois, /opt/work" ]]
}

@test "only the newest version of each JetBrains IDE counts" {
  given_jetbrains_trusted_locations WebStorm2026.1 '$USER_HOME$'
  given_jetbrains_trusted_locations WebStorm2026.2 '$USER_HOME$/work'

  run check_dev_ide_trusted_locations

  [[ "$(detail_of dev-tooling.ide-trusted-locations)" == "WebStorm2026.2: ~/work" ]]
}

@test "JetBrains IDE without trusted locations says none" {
  mkdir -p "$HOME/Library/Application Support/JetBrains/GoLand2026.2"

  run check_dev_ide_trusted_locations

  [[ "$(detail_of dev-tooling.ide-trusted-locations)" == "GoLand2026.2: none" ]]
}

@test "trusting the home folder warns" {
  given_jetbrains_trusted_locations IntelliJIdea2026.2 '$USER_HOME$/repositories' '$USER_HOME$'

  run check_dev_ide_trusted_locations

  [[ "$(detail_of dev-tooling.ide-trusted-locations)" == "IntelliJIdea2026.2: ~" ]]
}

@test "trusting the whole disk warns" {
  given_jetbrains_trusted_locations IntelliJIdea2026.2 /

  run check_dev_ide_trusted_locations

  [[ "$(result_of dev-tooling.ide-trusted-locations)" == "fail medium" ]]
}

@test "no JetBrains IDE skips the trusted locations" {
  run check_dev_ide_trusted_locations

  [[ "$(result_of dev-tooling.ide-trusted-locations)" == skipped ]]
}

@test "editor extensions are listed per editor" {
  mkdir -p "$HOME/.vscode/extensions" "$HOME/.cursor/extensions/ms-python.python-2026.1.0-darwin-arm64"
  echo '[{"identifier": {"id": "redhat.java"}}, {"identifier": {"id": "esbenp.prettier-vscode"}}]' \
    >"$HOME/.vscode/extensions/extensions.json"

  run check_dev_editor_extensions

  [[ "$(detail_of dev-tooling.editor-extensions)" == "Visual Studio Code: esbenp.prettier-vscode, redhat.java; Cursor: ms-python.python" ]]
}

@test "global packages leave out npm and the rustup commands" {
  stub_command npm '{"dependencies": {"npm": {}, "corepack": {}, "typescript": {}}}'
  stub_command pipx ""
  stub_command uv ""
  mkdir -p "$HOME/.cargo/bin"
  touch "$HOME/.cargo/bin/cargo" "$HOME/.cargo/bin/rustc" "$HOME/.cargo/bin/ripgrep"

  run check_dev_global_packages

  [[ "$(detail_of dev-tooling.global-packages)" == "npm: typescript; cargo: ripgrep" ]]
}

@test "JDKs are found by their release file" {
  given_jdk "$JAVA_VM_DIR/temurin-21.jdk/Contents/Home" 21.0.2
  given_jdk "$HOME/.sdkman/candidates/java/17.0.9-tem" 17.0.9

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Java: 21.0.2 ($JAVA_VM_DIR), 17.0.9 (SDKMAN)" ]]
}

@test "version manager symlinks are not counted twice" {
  given_folder "$HOME/.nvm/versions/node/v26.3.0"
  ln -s "$HOME/.nvm/versions/node/v26.3.0" "$HOME/.nvm/versions/node/current"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Node: 26.3.0 (nvm)" ]]
}

@test "Homebrew runtimes are found in the Cellar" {
  given_folder "$HOMEBREW_PREFIXES/Cellar/python@3.12/3.12.4_1"
  given_folder "$HOMEBREW_PREFIXES/Cellar/node@20/20.18.0"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Node: 20.18.0 (Homebrew); Python: 3.12.4 (Homebrew)" ]]
}

@test "conda and pyenv Pythons are found, not distribution names" {
  given_folder "$HOME/.pyenv/versions/3.11.9"
  given_folder "$HOME/.pyenv/versions/miniconda3-latest"
  mkdir -p "$HOME/miniconda3/conda-meta"
  touch "$HOME/miniconda3/conda-meta/python-3.12.2-hdf0ec26_0.json"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Python: 3.11.9 (pyenv), 3.12.2 (conda)" ]]
}

@test "Go and Ruby versions are found" {
  mkdir -p "$GO_INSTALL_DIR"
  printf 'go1.25.1\ntime 2026-09-02T00:00:00Z\n' >"$GO_INSTALL_DIR/VERSION"
  given_folder "$HOME/.rbenv/versions/3.3.5"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Go: 1.25.1 (go.dev); Ruby: 3.3.5 (rbenv)" ]]
}

@test "the rustup stable toolchain is named by its manifest" {
  local manifest="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/lib/rustlib/multirust-channel-manifest.toml"
  mkdir -p "$(dirname "$manifest")"
  printf '[pkg.cargo]\nversion = "1.90.0 (abc 2026-09-18)"\n[pkg.rust]\nversion = "1.90.0 (1159e78c4 2026-09-14)"\n' >"$manifest"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Rust: 1.90.0 (rustup)" ]]
}

@test "Command Line Tools and Homebrew compilers are found" {
  stub_command pkgutil $'package-id: com.apple.pkg.CLTools_Executables\nversion: 16.4.0.0.1.1747106510'
  given_folder "$HOMEBREW_PREFIXES/Cellar/gcc/15.1.0"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "C/C++: 16.4 (Command Line Tools), 15.1.0 (GCC, Homebrew)" ]]
}

@test "compilers are never run" {
  local command
  for command in clang gcc cc xcrun; do
    stub_script "$command" <<EOF
touch "$BATS_TEST_TMPDIR/compiler.ran"
EOF
  done

  run check_dev_runtimes

  [[ ! -e "$BATS_TEST_TMPDIR/compiler.ran" ]]
}

@test "no runtimes says none found" {
  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "none found" ]]
}

@test "runtime past its end of life warns" {
  given_folder "$HOME/.nvm/versions/node/v18.20.4"
  given_folder "$HOME/.nvm/versions/node/v26.3.0"

  run check_dev_runtime_support

  [[ "$(detail_of dev-tooling.runtime-support)" == "end of life: Node 18.20.4 (nvm, since 2000-01-01) (dates from endoflife.date, fetched $(date +%F))" ]]
}

@test "an end-of-life date that is not a date is ignored" {
  given_eol_cache nodejs $'18=2000-01-01\033[2K'
  given_folder "$HOME/.nvm/versions/node/v18.20.4"

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == pass ]]
}

@test "an end-of-life date that is not text is ignored" {
  mkdir -p "$EOL_CACHE_DIR"
  echo '{"result": {"releases": [{"name": "18", "eolFrom": 20000101}]}}' >"$EOL_CACHE_DIR/nodejs.json"
  given_folder "$HOME/.nvm/versions/node/v18.20.4"

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == pass ]]
}

@test "Java 8 is matched to its release" {
  given_jdk "$HOME/.sdkman/candidates/java/8.0.392-tem" 1.8.0_392

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == "fail medium" ]]
}

@test "versions missing from the table pass" {
  given_folder "$HOME/.pyenv/versions/3.13.1"

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == pass ]]
}

@test "an old Ruby cycle is found by its patch release" {
  given_folder "$HOME/.rbenv/versions/2.0.0-p648"

  run check_dev_runtime_support

  [[ "$(detail_of dev-tooling.runtime-support)" == "end of life: Ruby 2.0.0 (rbenv, since 2016-02-24)"* ]]
}

@test "a cache fetched today is used without calling the API" {
  given_eol_cache python 3.13=
  given_eol_cache go 1.27=
  given_eol_cache rust 1.90=

  run check_dev_runtime_support

  [[ -z "$(curl_calls)" ]]
}

@test "the detail says when the dates were fetched" {
  run check_dev_runtime_support

  [[ "$(detail_of dev-tooling.runtime-support)" == "dates from endoflife.date, fetched $(date +%F)" ]]
}

@test "an outdated cache is fetched again" {
  given_outdated_cache
  given_api_answer 200 "$(eol_releases 18=2999-01-01)"

  run check_dev_runtime_support

  [[ "$(jq -r '.result.releases[0].eolFrom' "$EOL_CACHE_DIR/nodejs.json")" == 2999-01-01 ]]
}

@test "missing products are fetched" {
  run check_dev_runtime_support

  [[ "$(curl_calls)" == *"https://endoflife.date/api/v1/products/python"* ]]
}

@test "--refresh-cache fetches a cache from today again" {
  REFRESH_CACHE=true

  run check_dev_runtime_support

  [[ "$(curl_calls)" == *"/products/nodejs"* ]]
}

@test "an error answer keeps the cached dates" {
  given_outdated_cache
  given_api_answer 503 '{"result": {"releases": []}}'

  run check_dev_runtime_support

  [[ "$(jq -r '.result.releases[0].eolFrom' "$EOL_CACHE_DIR/nodejs.json")" == 2000-01-01 ]]
}

@test "a 2xx answer without release data keeps the cached dates" {
  given_outdated_cache
  given_api_answer 200 '<html>maintenance</html>'

  run check_dev_runtime_support

  [[ "$(jq -r '.result.releases[0].eolFrom' "$EOL_CACHE_DIR/nodejs.json")" == 2000-01-01 ]]
}

@test "no download is left behind" {
  given_outdated_cache

  run check_dev_runtime_support

  [[ -z "$(find "$EOL_CACHE_DIR" -name '.*' -type f)" ]]
}

@test "no cache and no answer skips the check" {
  rm -rf "$EOL_CACHE_DIR"

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == skipped ]]
}

@test "--no-cache fetches the dates even with a cache from today" {
  NO_CACHE=true

  run check_dev_runtime_support

  [[ "$(curl_calls)" == *"/products/nodejs"* ]]
}

@test "--no-cache leaves the cache untouched" {
  NO_CACHE=true
  given_api_answer 200 "$(eol_releases 18=2999-01-01)"

  run check_dev_runtime_support

  [[ "$(jq -r '.result.releases[0].eolFrom' "$EOL_CACHE_DIR/nodejs.json")" == 2000-01-01 ]]
}

@test "--no-cache without an answer skips the check, even with a cache" {
  NO_CACHE=true

  run check_dev_runtime_support

  [[ "$(result_of dev-tooling.runtime-support)" == skipped ]]
}

# Usage: given_editor_settings settings_folder content
given_editor_settings() {
  mkdir -p "$HOME/Library/Application Support/$1/User"
  printf '%s\n' "$2" >"$HOME/Library/Application Support/$1/User/settings.json"
}

@test "workspace trust turned off warns, even with comments in settings" {
  given_editor_settings Code $'{\n  // keep it quiet\n  "security.workspace.trust.enabled": false,\n}'

  run check_dev_vscode_workspace_trust

  [[ "$(detail_of dev-tooling.vscode-workspace-trust)" == "turned off in Visual Studio Code" ]]
}

@test "commented-out workspace trust setting passes" {
  given_editor_settings Code $'{\n  // "security.workspace.trust.enabled": false\n}'

  run check_dev_vscode_workspace_trust

  [[ "$(result_of dev-tooling.vscode-workspace-trust)" == pass ]]
}

@test "Cursor is checked through its own folder" {
  given_editor_settings Cursor '{"security.workspace.trust.enabled": false}'

  run check_dev_vscode_workspace_trust

  [[ "$(detail_of dev-tooling.vscode-workspace-trust)" == "turned off in Cursor" ]]
}

@test "no VS Code family editor skips workspace trust" {
  run check_dev_vscode_workspace_trust

  [[ "$(result_of dev-tooling.vscode-workspace-trust)" == skipped ]]
}

@test "pnpm, Yarn and Bun global packages are read from their folders" {
  stub_command npm '{}'
  mkdir -p "$HOME/Library/pnpm/global/5" "$HOME/.config/yarn/global" "$HOME/.bun/install/global"
  echo '{"dependencies": {"@angular/cli": "^20", "vite": "^7"}}' >"$HOME/Library/pnpm/global/5/package.json"
  echo '{"dependencies": {"@vue/cli": "^5"}}' >"$HOME/.config/yarn/global/package.json"
  echo '{"dependencies": {"vitepress": "^2"}}' >"$HOME/.bun/install/global/package.json"

  run check_dev_global_packages

  [[ "$(detail_of dev-tooling.global-packages)" == "pnpm: @angular/cli, vite; Yarn: @vue/cli; Bun: vitepress" ]]
}

@test "Node installed with nodenv, n and pnpm is found" {
  given_folder "$HOME/.nodenv/versions/22.11.0"
  given_folder "$N_PREFIX/n/versions/node/24.1.0"
  given_folder "$HOME/Library/pnpm/nodejs/26.3.0"

  run check_dev_runtimes

  [[ "$(detail_of dev-tooling.runtimes)" == "Node: 22.11.0 (nodenv), 24.1.0 (n), 26.3.0 (pnpm)" ]]
}

@test "without a JavaScript package manager, npm settings are skipped" {
  PATH="$STUB_DIR:/usr/bin:/bin"

  run check_dev_npm_config

  [[ "$(result_of dev-tooling.npm-config)" == skipped ]]
}

@test "npm running install scripts warns" {
  stub_command npm ""

  run check_dev_npm_config

  [[ "$(result_of dev-tooling.npm-config)" == "fail low" ]]
}

@test "npm with ignore-scripts passes" {
  stub_command npm ""
  echo 'ignore-scripts=true' >"$HOME/.npmrc"

  run check_dev_npm_config

  [[ "$(result_of dev-tooling.npm-config)" == pass ]]
}

@test "turned off certificate checks and http registries fail" {
  stub_command npm ""
  printf 'strict-ssl=false\nignore-scripts=true\n' >"$HOME/.npmrc"
  printf 'enableStrictSsl: false\nnpmRegistryServer: "http://npm.acme.local"\n' >"$HOME/.yarnrc.yml"

  run check_dev_npm_config

  [[ "$(result_of dev-tooling.npm-config)" == "fail medium" ]]
  [[ "$(detail_of dev-tooling.npm-config)" == "strict-ssl=false in ~/.npmrc, enableStrictSsl: false in ~/.yarnrc.yml, http registry in ~/.yarnrc.yml" ]]
}

# Usage: given_processes "pid<TAB>program<TAB>args"...; ps lists them, and names each by its pid.
given_processes() {
  printf '%s\n' "$@" >"$STUB_DIR/processes"
  stub_script ps <<STUB
if [[ "\$*" == *"-p "* ]]; then
  awk -F'\t' -v pid="\${!#}" '\$1 == pid { print \$2 }' "$STUB_DIR/processes"
else
  awk -F'\t' '{ print \$1 " " \$3 }' "$STUB_DIR/processes"
fi
STUB
}

@test "a browser with a debugging port fails, showing only the flag" {
  given_processes $'101\t/Applications/Google Chrome.app/Contents/MacOS/Google Chrome\t/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/secret-profile' \
    $'102\t/usr/bin/login\tlogin -pf me'

  run check_dev_debug_ports

  [[ "$(result_of dev-tooling.debug-ports)" == "fail medium" ]]
  [[ "$(detail_of dev-tooling.debug-ports)" == "Google Chrome --remote-debugging-port=9222" ]]
}

@test "a Node inspector warns" {
  given_processes $'201\t/opt/homebrew/bin/node\tnode --inspect-brk=127.0.0.1:9229 server.js'

  run check_dev_debug_ports

  [[ "$(result_of dev-tooling.debug-ports)" == "fail low" ]]
  [[ "$(detail_of dev-tooling.debug-ports)" == "node --inspect-brk=127.0.0.1:9229" ]]
}

@test "processes without debugging flags pass" {
  given_processes $'301\t/opt/homebrew/bin/node\tnode --inspect-publish-uid=http server.js'

  run check_dev_debug_ports

  [[ "$(result_of dev-tooling.debug-ports)" == pass ]]
}

@test "API clients and mobile tools are listed from the catalogue" {
  PATH="$STUB_DIR:/usr/bin:/bin"
  given_app Postman com.postmanlabs.mac 11.2
  stub_command eas ""

  run check_dev_api_clients
  run check_dev_mobile_dev

  [[ "$(detail_of dev-tooling.api-clients)" == "Postman 11.2" ]]
  [[ "$(detail_of dev-tooling.mobile-dev)" == "EAS CLI" ]]
}
