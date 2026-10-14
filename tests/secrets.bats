#!/usr/bin/env bats

load test_helper

# Built at runtime so this file holds no secret-shaped strings.
GITHUB_TOKEN_VALUE="ghp_$(printf 'a%.0s' {1..36})"
AWS_KEY_VALUE="AKIA$(printf 'B%.0s' {1..16})"

setup() {
  setup_audit checks/50-secrets.sh
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

@test "GitHub token in .zshrc fails with file and line" {
  printf '# tools\nexport GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN_VALUE" >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == *"~/.zshrc:2 (GitHub token)"* ]]
}

@test "secret values are never printed" {
  printf 'export GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN_VALUE" >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$output" != *"$GITHUB_TOKEN_VALUE"* ]]
}

@test "secret values are never stored in the results" {
  printf 'export GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN_VALUE" >"$HOME/.zshrc"

  run check_secrets_dotfiles

  ! grep -qF "$GITHUB_TOKEN_VALUE" "$RESULTS_FILE"
}

@test "AWS access key in .zprofile fails" {
  printf 'export AWS_ACCESS_KEY_ID=%s\n' "$AWS_KEY_VALUE" >"$HOME/.zprofile"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == *"~/.zprofile:1 (AWS access key)"* ]]
}

@test "password inside a connection URL fails" {
  echo 'export DATABASE_URL=postgres://app:hunter2hunter2@db.local:5432/app' >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == *"(Password in URL)"* ]]
}

@test "token read from the Keychain passes" {
  echo 'export GITHUB_TOKEN=$(security find-generic-password -w -s github)' >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$(result_of secrets.dotfiles)" == pass ]]
}

@test "token taken from another variable passes" {
  echo 'export NPM_TOKEN="${GITHUB_TOKEN}"' >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$(result_of secrets.dotfiles)" == pass ]]
}

@test "npm token referencing an environment variable passes" {
  echo '//registry.npmjs.org/:_authToken=${NPM_TOKEN}' >"$HOME/.npmrc"

  run check_secrets_dotfiles

  [[ "$(result_of secrets.dotfiles)" == pass ]]
}

@test "password in .netrc fails" {
  printf 'machine example.com\n  login me\n  password hunter2\n' >"$HOME/.netrc"

  run check_secrets_netrc

  [[ "$(detail_of secrets.netrc)" == "password on line 3" ]]
}

@test "static AWS keys warn" {
  mkdir -p "$HOME/.aws"
  printf '[default]\naws_access_key_id = x\naws_secret_access_key = y\n' >"$HOME/.aws/credentials"

  run check_secrets_aws

  [[ "$(result_of secrets.aws)" == "fail medium" ]]
}

@test "no AWS credentials file passes" {
  run check_secrets_aws

  [[ "$(result_of secrets.aws)" == pass ]]
}

@test "inline Docker registry login fails and names the registry" {
  mkdir -p "$HOME/.docker"
  echo '{"auths": {"ghcr.io": {"auth": "dXNlcjpwYXNz"}}}' >"$HOME/.docker/config.json"

  run check_secrets_docker

  [[ "$(detail_of secrets.docker)" == "plaintext logins for: ghcr.io" ]]
}

@test "Docker logins in a credential store pass" {
  mkdir -p "$HOME/.docker"
  echo '{"auths": {"ghcr.io": {}}, "credsStore": "osxkeychain"}' >"$HOME/.docker/config.json"

  run check_secrets_docker

  [[ "$(result_of secrets.docker)" == pass ]]
}

@test "Docker without a credential store warns" {
  mkdir -p "$HOME/.docker"
  echo '{"auths": {}}' >"$HOME/.docker/config.json"

  run check_secrets_docker

  [[ "$(result_of secrets.docker)" == "fail low" ]]
}

@test "invalid Docker config warns" {
  mkdir -p "$HOME/.docker"
  echo '{not json' >"$HOME/.docker/config.json"

  run check_secrets_docker

  [[ "$(detail_of secrets.docker)" == "~/.docker/config.json is not valid JSON" ]]
}

@test "plaintext Maven password fails with its line" {
  mkdir -p "$HOME/.m2"
  printf '<settings>\n<servers>\n<server><id>a</id><password>plain</password></server>\n</servers>\n</settings>\n' >"$HOME/.m2/settings.xml"

  run check_secrets_maven

  [[ "$(detail_of secrets.maven)" == "plaintext <password> in ~/.m2/settings.xml on line 3" ]]
}

@test "encrypted and environment Maven passwords pass" {
  mkdir -p "$HOME/.m2"
  printf '<password>{COQLCE6DU6GtcS5P=}</password>\n<password>${env.NEXUS_PASSWORD}</password>\n' >"$HOME/.m2/settings.xml"

  run check_secrets_maven

  [[ "$(result_of secrets.maven)" == pass ]]
}

@test "static Kubernetes token warns" {
  mkdir -p "$HOME/.kube"
  printf 'users:\n- name: admin\n  user:\n    token: abc\n' >"$HOME/.kube/config"

  run check_secrets_kube

  [[ "$(detail_of secrets.kube)" == "static tokens or keys in ~/.kube/config" ]]
}

@test "Kubernetes exec credential plugin passes" {
  mkdir -p "$HOME/.kube"
  printf 'users:\n- name: dev\n  user:\n    exec:\n      command: kubelogin\n' >"$HOME/.kube/config"

  run check_secrets_kube

  [[ "$(result_of secrets.kube)" == pass ]]
}

@test "every file in KUBECONFIG is checked" {
  printf '    client-key-data: abc\n' >"$BATS_TEST_TMPDIR/second"
  export KUBECONFIG="$HOME/.kube/config:$BATS_TEST_TMPDIR/second"

  run check_secrets_kube

  [[ "$(result_of secrets.kube)" == "fail medium" ]]
}

@test "OpenTofu registry credentials file warns" {
  mkdir -p "$HOME/.terraform.d"
  echo '{}' >"$HOME/.terraform.d/credentials.tfrc.json"

  run check_secrets_terraform

  [[ "$(result_of secrets.terraform)" == "fail medium" ]]
}

@test "GitHub CLI token in hosts.yml warns" {
  mkdir -p "$HOME/.config/gh"
  printf 'github.com:\n    oauth_token: x\n    user: me\n' >"$HOME/.config/gh/hosts.yml"

  run check_secrets_gh

  [[ "$(result_of secrets.gh)" == "fail medium" ]]
}

# Usage: given_ssh_key name passphrase [ssh-keygen options...]
given_ssh_key() {
  local name="$1" passphrase="$2"
  shift 2
  ssh-keygen -q -t ed25519 "$@" -N "$passphrase" -C test -f "$HOME/.ssh/$name"
}

@test "~/.ssh readable by others fails" {
  chmod 755 "$HOME/.ssh"

  run check_secrets_ssh_dir

  [[ "$(detail_of secrets.ssh-dir)" == "mode 755" ]]
}

@test "~/.ssh only readable by its owner passes" {
  run check_secrets_ssh_dir

  [[ "$(result_of secrets.ssh-dir)" == pass ]]
}

@test "missing ~/.ssh is skipped" {
  rmdir "$HOME/.ssh"

  run check_secrets_ssh_dir

  [[ "$(result_of secrets.ssh-dir)" == skipped ]]
}

@test "private key readable by others fails" {
  given_ssh_key id_ed25519 "a passphrase"
  chmod 644 "$HOME/.ssh/id_ed25519"

  run check_secrets_ssh_key_permissions

  [[ "$(detail_of secrets.ssh-key-permissions)" == "~/.ssh/id_ed25519 (644)" ]]
}

@test "public keys are not mistaken for private keys" {
  given_ssh_key id_ed25519 "a passphrase"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"

  run check_secrets_ssh_key_permissions

  [[ "$(result_of secrets.ssh-key-permissions)" == pass ]]
}

@test "private key without a passphrase fails" {
  given_ssh_key id_ed25519 ""

  run check_secrets_ssh_key_passphrases

  [[ "$(detail_of secrets.ssh-key-passphrases)" == "no passphrase: ~/.ssh/id_ed25519" ]]
}

@test "private key with a passphrase passes" {
  given_ssh_key id_ed25519 "a passphrase"

  run check_secrets_ssh_key_passphrases

  [[ "$(result_of secrets.ssh-key-passphrases)" == pass ]]
}

@test "short RSA key warns" {
  ssh-keygen -q -t rsa -b 2048 -N "" -C test -f "$HOME/.ssh/id_rsa"

  run check_secrets_ssh_key_strength

  [[ "$(detail_of secrets.ssh-key-strength)" == "~/.ssh/id_rsa (2048-bit RSA)" ]]
}

@test "ed25519 key passes" {
  given_ssh_key id_ed25519 ""

  run check_secrets_ssh_key_strength

  [[ "$(result_of secrets.ssh-key-strength)" == pass ]]
}

@test "agent forwarded to every host warns" {
  printf 'Host *\n  ForwardAgent yes\n' >"$HOME/.ssh/config"

  run check_secrets_ssh_agent_forwarding

  [[ "$(result_of secrets.ssh-agent-forwarding)" == "fail medium" ]]
}

@test "agent forwarded to one host passes" {
  printf 'Host bastion\n  ForwardAgent yes\n' >"$HOME/.ssh/config"

  run check_secrets_ssh_agent_forwarding

  [[ "$(result_of secrets.ssh-agent-forwarding)" == pass ]]
}

@test "authorized keys warn with their count" {
  printf '# laptop\nssh-ed25519 AAAA one\nssh-ed25519 AAAA two\n' >"$HOME/.ssh/authorized_keys"

  run check_secrets_ssh_authorized_keys

  [[ "$(detail_of secrets.ssh-authorized-keys)" == "2 key(s) in ~/.ssh/authorized_keys can log in when Remote Login is on" ]]
}

@test "GnuPG home readable by others fails" {
  mkdir -m 755 "$HOME/.gnupg"

  run check_secrets_gnupg_dir

  [[ "$(detail_of secrets.gnupg-dir)" == "~/.gnupg has mode 755" ]]
}

@test "GnuPG home only readable by its owner passes" {
  mkdir -m 700 "$HOME/.gnupg"

  run check_secrets_gnupg_dir

  [[ "$(result_of secrets.gnupg-dir)" == pass ]]
}

@test "Yarn token in .yarnrc.yml fails without its value" {
  printf 'npmScopes:\n  acme:\n    npmAuthToken: "plain-yarn-value"\n' >"$HOME/.yarnrc.yml"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == "~/.yarnrc.yml:3 (Yarn token)" ]]
  ! grep -qF plain-yarn-value "$RESULTS_FILE"
}

@test "Yarn token read from an environment variable passes" {
  echo 'npmAuthToken: "${NPM_TOKEN}"' >"$HOME/.yarnrc.yml"

  run check_secrets_dotfiles

  [[ "$(result_of secrets.dotfiles)" == pass ]]
}

@test "Yarn classic token in .yarnrc fails" {
  echo '"//registry.npmjs.org/:_authToken" plain-yarn-value' >"$HOME/.yarnrc"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == "~/.yarnrc:1 (npm token)" ]]
}

@test "Bun registry token in .bunfig.toml fails" {
  printf '[install.scopes]\nacme = { url = "https://npm.acme.dev/", token = "plain-bun-value" }\n' >"$HOME/.bunfig.toml"

  run check_secrets_dotfiles

  [[ "$(detail_of secrets.dotfiles)" == "~/.bunfig.toml:2 (Registry token)" ]]
}

@test "Bun registry token from an environment variable passes" {
  printf '[install.scopes]\nacme = { url = "https://npm.acme.dev/", token = "$ACME_TOKEN" }\n' >"$HOME/.bunfig.toml"

  run check_secrets_dotfiles

  [[ "$(result_of secrets.dotfiles)" == pass ]]
}

@test "plaintext Gradle signing password fails with its line only" {
  mkdir -p "$HOME/.gradle"
  printf 'org.gradle.jvmargs=-Xmx4g\nMYAPP_UPLOAD_STORE_PASSWORD=plain-gradle-value\n' >"$HOME/.gradle/gradle.properties"

  run check_secrets_gradle

  [[ "$(result_of secrets.gradle)" == "fail high" ]]
  [[ "$(detail_of secrets.gradle)" == "~/.gradle/gradle.properties on line 2" ]]
  ! grep -qF plain-gradle-value "$RESULTS_FILE"
}

@test "Gradle properties without passwords pass" {
  mkdir -p "$HOME/.gradle"
  printf 'org.gradle.jvmargs=-Xmx4g\n# signing.password=\nMYAPP_UPLOAD_STORE_PASSWORD=\n' >"$HOME/.gradle/gradle.properties"

  run check_secrets_gradle

  [[ "$(result_of secrets.gradle)" == pass ]]
}

@test "CLI logins only readable by you pass and are named" {
  mkdir -p "$HOME/.config/configstore" "$HOME/.expo"
  echo '{"tokens": {"refresh_token": "x"}}' >"$HOME/.config/configstore/firebase-tools.json"
  echo '{"auth": {"sessionSecret": "x"}}' >"$HOME/.expo/state.json"
  chmod 600 "$HOME/.config/configstore/firebase-tools.json" "$HOME/.expo/state.json"

  run check_secrets_cli_logins

  [[ "$(result_of secrets.cli-logins)" == pass ]]
  [[ "$(detail_of secrets.cli-logins)" == "Firebase, Expo" ]]
}

@test "a CLI login readable by others warns" {
  mkdir -p "$HOME/Library/Application Support/com.vercel.cli"
  echo '{"token": "x"}' >"$HOME/Library/Application Support/com.vercel.cli/auth.json"
  chmod 644 "$HOME/Library/Application Support/com.vercel.cli/auth.json"

  run check_secrets_cli_logins

  [[ "$(result_of secrets.cli-logins)" == "fail medium" ]]
  [[ "$(detail_of secrets.cli-logins)" == "readable by others: ~/Library/Application Support/com.vercel.cli/auth.json (644)" ]]
}

@test "a CLI config without a token is not a login" {
  mkdir -p "$HOME/.config/configstore"
  echo '{"usage": true}' >"$HOME/.config/configstore/firebase-tools.json"

  run check_secrets_cli_logins

  [[ "$(detail_of secrets.cli-logins)" == "none found" ]]
}

@test "App Store Connect keys are listed" {
  mkdir -p "$HOME/.appstoreconnect/private_keys"
  touch "$HOME/.appstoreconnect/private_keys/AuthKey_ABC123.p8"
  chmod 600 "$HOME/.appstoreconnect/private_keys/AuthKey_ABC123.p8"

  run check_secrets_cli_logins

  [[ "$(detail_of secrets.cli-logins)" == "App Store Connect key" ]]
}
