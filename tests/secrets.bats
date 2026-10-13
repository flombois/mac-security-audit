#!/usr/bin/env bats

load test_helper

# Built at runtime so this file holds no secret-shaped strings.
GITHUB_TOKEN_VALUE="ghp_$(printf 'a%.0s' {1..36})"
AWS_KEY_VALUE="AKIA$(printf 'B%.0s' {1..16})"

setup() {
  setup_audit checks/50-secrets.sh
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

  [[ "$(status_of secrets.dotfiles)" == pass ]]
}

@test "token taken from another variable passes" {
  echo 'export NPM_TOKEN="${GITHUB_TOKEN}"' >"$HOME/.zshrc"

  run check_secrets_dotfiles

  [[ "$(status_of secrets.dotfiles)" == pass ]]
}

@test "npm token referencing an environment variable passes" {
  echo '//registry.npmjs.org/:_authToken=${NPM_TOKEN}' >"$HOME/.npmrc"

  run check_secrets_dotfiles

  [[ "$(status_of secrets.dotfiles)" == pass ]]
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

  [[ "$(status_of secrets.aws)" == warn ]]
}

@test "no AWS credentials file passes" {
  run check_secrets_aws

  [[ "$(status_of secrets.aws)" == pass ]]
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

  [[ "$(status_of secrets.docker)" == pass ]]
}

@test "Docker without a credential store warns" {
  mkdir -p "$HOME/.docker"
  echo '{"auths": {}}' >"$HOME/.docker/config.json"

  run check_secrets_docker

  [[ "$(status_of secrets.docker)" == warn ]]
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

  [[ "$(status_of secrets.maven)" == pass ]]
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

  [[ "$(status_of secrets.kube)" == pass ]]
}

@test "every file in KUBECONFIG is checked" {
  printf '    client-key-data: abc\n' >"$BATS_TEST_TMPDIR/second"
  export KUBECONFIG="$HOME/.kube/config:$BATS_TEST_TMPDIR/second"

  run check_secrets_kube

  [[ "$(status_of secrets.kube)" == warn ]]
}

@test "OpenTofu registry credentials file warns" {
  mkdir -p "$HOME/.terraform.d"
  echo '{}' >"$HOME/.terraform.d/credentials.tfrc.json"

  run check_secrets_terraform

  [[ "$(status_of secrets.terraform)" == warn ]]
}

@test "GitHub CLI token in hosts.yml warns" {
  mkdir -p "$HOME/.config/gh"
  printf 'github.com:\n    oauth_token: x\n    user: me\n' >"$HOME/.config/gh/hosts.yml"

  run check_secrets_gh

  [[ "$(status_of secrets.gh)" == warn ]]
}

@test "repository scan is skipped unless requested" {
  run check_secrets_repos

  [[ "$(status_of secrets.repos)" == skip ]]
}

@test "repository with gitleaks findings fails with the count" {
  SCAN_REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  mkdir -p "$SCAN_REPOS_DIR/leaky/.git"
  stub_script gitleaks <<'EOF'
while [[ $# -gt 0 ]]; do
  [[ "$1" == --report-path ]] && echo '[{"RuleID": "generic-api-key"}, {"RuleID": "aws-access-token"}]' >"$2"
  shift
done
EOF

  run check_secrets_repos

  [[ "$(detail_of secrets.repos)" == *"/repos/leaky: 2 finding(s)" ]]
}

@test "repositories without gitleaks findings pass" {
  SCAN_REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  mkdir -p "$SCAN_REPOS_DIR/clean/.git"
  stub_script gitleaks <<'EOF'
while [[ $# -gt 0 ]]; do
  [[ "$1" == --report-path ]] && echo '[]' >"$2"
  shift
done
EOF

  run check_secrets_repos

  [[ "$(status_of secrets.repos)" == pass ]]
}
