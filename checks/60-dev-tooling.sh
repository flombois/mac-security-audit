# Developer tooling: SSH, git, package managers, containers, Kubernetes and AI coding tools.

RSA_MIN_BITS=3072

run_dev_tooling_checks() {
  check_dev_ssh_dir
  check_dev_ssh_key_permissions
  check_dev_ssh_key_passphrases
  check_dev_ssh_key_strength
  check_dev_ssh_agent_forwarding
  check_dev_ssh_authorized_keys
  check_dev_gnupg_dir
  check_dev_git_credentials
  check_dev_git_signing
  check_dev_brew_outdated
  check_dev_brew_taps
  check_dev_docker_rootless
  check_dev_docker_mounts
  check_dev_kube_contexts
  check_dev_claude_permissions
  check_dev_claude_mcp
  check_dev_ide_manual_review
}

check_dev_ssh_dir() {
  if [[ ! -d "$HOME/.ssh" ]]; then
    report_skip dev-tooling.ssh-dir "~/.ssh only readable by you" "no ~/.ssh"
    return
  fi
  local mode
  mode="$(file_mode "$HOME/.ssh")"
  if [[ "$mode" == 700 ]]; then
    report_pass dev-tooling.ssh-dir "~/.ssh only readable by you"
  else
    report_fail dev-tooling.ssh-dir "~/.ssh only readable by you" "mode $mode" "Run: chmod 700 ~/.ssh"
  fi
}

check_dev_ssh_key_permissions() {
  local keys
  keys="$(ssh_keys_readable_by_others | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass dev-tooling.ssh-key-permissions "SSH private keys only readable by you"
  else
    report_fail dev-tooling.ssh-key-permissions "SSH private keys only readable by you" "$keys" \
      "Run: chmod 600 on each key"
  fi
}

ssh_keys_readable_by_others() {
  local key mode
  ssh_private_keys | while IFS= read -r key; do
    mode="$(file_mode "$key")"
    if [[ "$mode" != 600 && "$mode" != 400 ]]; then
      echo "$(tilde_path "$key") ($mode)"
    fi
  done
}

check_dev_ssh_key_passphrases() {
  local keys
  keys="$(ssh_private_keys | while IFS= read -r key; do
    # Deriving the public key with an empty passphrase only succeeds on unprotected keys.
    if ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
      tilde_path "$key"
    fi
  done | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass dev-tooling.ssh-key-passphrases "SSH private keys protected by a passphrase"
  else
    report_fail dev-tooling.ssh-key-passphrases "SSH private keys protected by a passphrase" "no passphrase: $keys" \
      "Run: ssh-keygen -p -f KEY, and add 'UseKeychain yes' to ~/.ssh/config; or move keys to Secretive / 1Password"
  fi
}

check_dev_ssh_key_strength() {
  local keys
  keys="$(ssh_private_keys | while IFS= read -r key; do
    ssh-keygen -l -f "$key" 2>/dev/null | awk -v key="$(tilde_path "$key")" -v min="$RSA_MIN_BITS" '
      $NF == "(DSA)" || ($NF == "(RSA)" && $1 < min) { print key " (" $1 "-bit " substr($NF, 2, length($NF) - 2) ")" }'
  done | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass dev-tooling.ssh-key-strength "SSH keys use strong algorithms"
  else
    report_warn dev-tooling.ssh-key-strength "SSH keys use strong algorithms" "$keys" \
      "Replace them with ed25519 keys: ssh-keygen -t ed25519"
  fi
}

# Prints the private key files directly in ~/.ssh.
ssh_private_keys() {
  local file
  find "$HOME/.ssh" -maxdepth 1 -type f 2>/dev/null | sort | while IFS= read -r file; do
    if head -1 "$file" 2>/dev/null | grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
      echo "$file"
    fi
  done
}

check_dev_ssh_agent_forwarding() {
  if awk '
      tolower($1) == "host" { host = $2; next }
      tolower($1) == "forwardagent" && tolower($2) == "yes" && (host == "" || host == "*") { found = 1 }
      END { exit !found }' "$HOME/.ssh/config" 2>/dev/null; then
    report_warn dev-tooling.ssh-agent-forwarding "SSH agent not forwarded to every host" "ForwardAgent yes applies to all hosts" \
      "Enable ForwardAgent only under specific Host blocks, or use ProxyJump instead"
  else
    report_pass dev-tooling.ssh-agent-forwarding "SSH agent not forwarded to every host"
  fi
}

check_dev_ssh_authorized_keys() {
  local count
  count="$(grep -cvE '^[[:space:]]*(#|$)' "$HOME/.ssh/authorized_keys" 2>/dev/null)" || count=0
  if [[ "$count" -eq 0 ]]; then
    report_pass dev-tooling.ssh-authorized-keys "No keys allowed to log in to this Mac"
  else
    report_warn dev-tooling.ssh-authorized-keys "No keys allowed to log in to this Mac" \
      "$count key(s) in ~/.ssh/authorized_keys can log in when Remote Login is on" \
      "Remove keys you don't need"
  fi
}

check_dev_gnupg_dir() {
  local dir="${GNUPGHOME:-$HOME/.gnupg}" mode
  if [[ ! -d "$dir" ]]; then
    report_skip dev-tooling.gnupg-dir "GnuPG home only readable by you" "no $(tilde_path "$dir")"
    return
  fi
  mode="$(file_mode "$dir")"
  if [[ "$mode" == 700 ]]; then
    report_pass dev-tooling.gnupg-dir "GnuPG home only readable by you"
  else
    report_fail dev-tooling.gnupg-dir "GnuPG home only readable by you" "$(tilde_path "$dir") has mode $mode" \
      "Run: chmod -R go-rwx $(tilde_path "$dir")"
  fi
}

check_dev_git_credentials() {
  local helpers
  helpers="$(git config --get-all credential.helper 2>/dev/null | join_lines)"
  if [[ "$helpers" == *store* ]]; then
    report_fail dev-tooling.git-credentials "Git credentials kept in the Keychain" "credential.helper: $helpers (plaintext ~/.git-credentials)" \
      "Run: git config --global credential.helper osxkeychain, then delete ~/.git-credentials"
  else
    report_pass dev-tooling.git-credentials "Git credentials kept in the Keychain" "credential.helper: ${helpers:-none}"
  fi
}

check_dev_git_signing() {
  if [[ "$(git config --get commit.gpgsign 2>/dev/null)" == true ]]; then
    report_pass dev-tooling.git-signing "Git commits signed" "format: $(git config --get gpg.format 2>/dev/null || echo openpgp)"
  else
    report_warn dev-tooling.git-signing "Git commits signed" "commit.gpgsign is off" \
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
    report_warn dev-tooling.brew-outdated "Homebrew packages up to date" "$outdated" \
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
  report_info dev-tooling.brew-taps "Third-party Homebrew taps" "${taps:-none}"
}

check_dev_docker_rootless() {
  if ! docker_running; then
    report_skip dev-tooling.docker-rootless "Docker daemon rootless" "Docker is not running"
    return
  fi
  if docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -q rootless; then
    report_pass dev-tooling.docker-rootless "Docker daemon rootless"
  else
    report_warn dev-tooling.docker-rootless "Docker daemon rootless" "the daemon runs as root inside its VM" \
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
    report_warn dev-tooling.docker-mounts "Containers don't mount your home or the Docker socket" "$containers" \
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
    report_warn dev-tooling.kube-contexts "No production Kubernetes contexts" "$contexts" \
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
    report_warn dev-tooling.claude-permissions "Claude Code asks before risky actions" "$risks" \
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
  report_info dev-tooling.claude-mcp "Claude Code MCP servers" \
    "user-level: ${servers:-none}; run /mcp in Claude Code to also see claude.ai connectors and project servers"
}

check_dev_ide_manual_review() {
  report_manual dev-tooling.ide "Review JetBrains trusted projects and plugins" \
    "Settings › Build, Execution, Deployment › Trusted Locations: keep it short; remove plugins you don't use"
}
