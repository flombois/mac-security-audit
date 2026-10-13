#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/60-dev-tooling.sh
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

# Usage: given_ssh_key name passphrase [ssh-keygen options...]
given_ssh_key() {
  local name="$1" passphrase="$2"
  shift 2
  ssh-keygen -q -t ed25519 "$@" -N "$passphrase" -C test -f "$HOME/.ssh/$name"
}

@test "~/.ssh readable by others fails" {
  chmod 755 "$HOME/.ssh"

  run check_dev_ssh_dir

  [[ "$(detail_of dev-tooling.ssh-dir)" == "mode 755" ]]
}

@test "~/.ssh only readable by its owner passes" {
  run check_dev_ssh_dir

  [[ "$(status_of dev-tooling.ssh-dir)" == pass ]]
}

@test "missing ~/.ssh is skipped" {
  rmdir "$HOME/.ssh"

  run check_dev_ssh_dir

  [[ "$(status_of dev-tooling.ssh-dir)" == skip ]]
}

@test "private key readable by others fails" {
  given_ssh_key id_ed25519 "a passphrase"
  chmod 644 "$HOME/.ssh/id_ed25519"

  run check_dev_ssh_key_permissions

  [[ "$(detail_of dev-tooling.ssh-key-permissions)" == "~/.ssh/id_ed25519 (644)" ]]
}

@test "public keys are not mistaken for private keys" {
  given_ssh_key id_ed25519 "a passphrase"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"

  run check_dev_ssh_key_permissions

  [[ "$(status_of dev-tooling.ssh-key-permissions)" == pass ]]
}

@test "private key without a passphrase fails" {
  given_ssh_key id_ed25519 ""

  run check_dev_ssh_key_passphrases

  [[ "$(detail_of dev-tooling.ssh-key-passphrases)" == "no passphrase: ~/.ssh/id_ed25519" ]]
}

@test "private key with a passphrase passes" {
  given_ssh_key id_ed25519 "a passphrase"

  run check_dev_ssh_key_passphrases

  [[ "$(status_of dev-tooling.ssh-key-passphrases)" == pass ]]
}

@test "short RSA key warns" {
  ssh-keygen -q -t rsa -b 2048 -N "" -C test -f "$HOME/.ssh/id_rsa"

  run check_dev_ssh_key_strength

  [[ "$(detail_of dev-tooling.ssh-key-strength)" == "~/.ssh/id_rsa (2048-bit RSA)" ]]
}

@test "ed25519 key passes" {
  given_ssh_key id_ed25519 ""

  run check_dev_ssh_key_strength

  [[ "$(status_of dev-tooling.ssh-key-strength)" == pass ]]
}

@test "agent forwarded to every host warns" {
  printf 'Host *\n  ForwardAgent yes\n' >"$HOME/.ssh/config"

  run check_dev_ssh_agent_forwarding

  [[ "$(status_of dev-tooling.ssh-agent-forwarding)" == warn ]]
}

@test "agent forwarded to one host passes" {
  printf 'Host bastion\n  ForwardAgent yes\n' >"$HOME/.ssh/config"

  run check_dev_ssh_agent_forwarding

  [[ "$(status_of dev-tooling.ssh-agent-forwarding)" == pass ]]
}

@test "authorized keys warn with their count" {
  printf '# laptop\nssh-ed25519 AAAA one\nssh-ed25519 AAAA two\n' >"$HOME/.ssh/authorized_keys"

  run check_dev_ssh_authorized_keys

  [[ "$(detail_of dev-tooling.ssh-authorized-keys)" == "2 key(s) in ~/.ssh/authorized_keys can log in when Remote Login is on" ]]
}

@test "GnuPG home readable by others fails" {
  mkdir -m 755 "$HOME/.gnupg"

  run check_dev_gnupg_dir

  [[ "$(detail_of dev-tooling.gnupg-dir)" == "~/.gnupg has mode 755" ]]
}

@test "GnuPG home only readable by its owner passes" {
  mkdir -m 700 "$HOME/.gnupg"

  run check_dev_gnupg_dir

  [[ "$(status_of dev-tooling.gnupg-dir)" == pass ]]
}

@test "plaintext git credential store fails" {
  git config --global credential.helper store

  run check_dev_git_credentials

  [[ "$(status_of dev-tooling.git-credentials)" == fail ]]
}

@test "Keychain git credential helper passes" {
  git config --global credential.helper osxkeychain

  run check_dev_git_credentials

  [[ "$(status_of dev-tooling.git-credentials)" == pass ]]
}

@test "unsigned commits warn" {
  run check_dev_git_signing

  [[ "$(status_of dev-tooling.git-signing)" == warn ]]
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

  [[ "$(status_of dev-tooling.docker-rootless)" == pass ]]
}

@test "rootful Docker warns" {
  stub_script docker <<'EOF'
[[ "$1" == info && "$*" == *SecurityOptions* ]] && echo '["name=seccomp,profile=builtin","name=cgroupns"]'
exit 0
EOF

  run check_dev_docker_rootless

  [[ "$(status_of dev-tooling.docker-rootless)" == warn ]]
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

  [[ "$(status_of dev-tooling.claude-permissions)" == pass ]]
}

@test "Claude Code MCP servers are listed" {
  echo '{"mcpServers": {"github": {}, "idea": {}}}' >"$HOME/.claude.json"

  run check_dev_claude_mcp

  [[ "$(detail_of dev-tooling.claude-mcp)" == "user-level: github, idea;"* ]]
}
