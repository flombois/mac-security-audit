# Secrets at rest: credentials in plaintext files. Findings name the file and line, never the value.

SHELL_DOTFILES=".zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .npmrc .pypirc .git-credentials"
# "name|extended regex"; the name is everything before the first "|".
SECRET_RULES=(
  "AWS access key|AKIA[0-9A-Z]{16}"
  "GitHub token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}"
  "GitLab token|glpat-[A-Za-z0-9_-]{20,}"
  "Slack token|xox[abprs]-[A-Za-z0-9-]{10,}"
  "Anthropic API key|sk-ant-[A-Za-z0-9_-]{20,}"
  "OpenAI API key|sk-(proj-)?[A-Za-z0-9]{20,}"
  "Private key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "npm token|_authToken=[^\$[:space:]]"
  "Password in URL|://[^/:@[:space:]]+:[^/@[:space:]\$]+@"
  "Hard-coded secret variable|[A-Z_]*(PASSWORD|SECRET|TOKEN|API_KEY|APIKEY|ACCESS_KEY)[A-Z_]*=[\"']?[^\"'\$({[:space:]][^\"'[:space:]]{7,}"
)
SCAN_REPOS_DIR="${SCAN_REPOS_DIR:-}"

run_secrets_checks() {
  check_secrets_dotfiles
  check_secrets_netrc
  check_secrets_aws
  check_secrets_docker
  check_secrets_maven
  check_secrets_kube
  check_secrets_terraform
  check_secrets_gh
  check_secrets_repos
}

check_secrets_dotfiles() {
  local findings
  findings="$(dotfile_secret_findings | join_lines)"
  if [[ -z "$findings" ]]; then
    report_pass secrets.dotfiles "No secrets in shell and tool dotfiles"
  else
    report_fail secrets.dotfiles "No secrets in shell and tool dotfiles" "$findings" \
      "Move them to the Keychain (security add-generic-password) or a password manager CLI, and rotate them"
  fi
}

# Prints "~/file:line (rule)" for each line that matches a secret rule.
dotfile_secret_findings() {
  local name file rule line
  for name in $SHELL_DOTFILES; do
    file="$HOME/$name"
    [[ -f "$file" ]] || continue
    for rule in "${SECRET_RULES[@]}"; do
      grep -nE -- "${rule#*|}" "$file" 2>/dev/null | cut -d: -f1 | while IFS= read -r line; do
        echo "$(tilde_path "$file"):$line (${rule%%|*})"
      done
    done
  done
}

check_secrets_netrc() {
  local file="$HOME/.netrc" lines
  lines="$(grep -nE '(^|[[:space:]])password[[:space:]]+[^[:space:]]' "$file" 2>/dev/null | cut -d: -f1 | join_lines)"
  if [[ -z "$lines" ]]; then
    report_pass secrets.netrc "No passwords in ~/.netrc"
  else
    report_fail secrets.netrc "No passwords in ~/.netrc" "password on line $lines" \
      "Remove the passwords; use a credential helper or token from the Keychain"
  fi
}

check_secrets_aws() {
  local file="$HOME/.aws/credentials" profiles
  profiles="$(grep -cE '^[[:space:]]*aws_secret_access_key' "$file" 2>/dev/null)" || profiles=0
  if [[ "$profiles" -eq 0 ]]; then
    report_pass secrets.aws "No static AWS keys"
  else
    report_warn secrets.aws "No static AWS keys" "$profiles profile(s) in ~/.aws/credentials hold access keys" \
      "Use IAM Identity Center (aws configure sso) for short-lived credentials"
  fi
}

check_secrets_docker() {
  local file="$HOME/.docker/config.json" registries creds_store
  if [[ ! -f "$file" ]]; then
    report_pass secrets.docker "Docker registry logins kept in the Keychain" "no ~/.docker/config.json"
    return
  fi
  if ! registries="$(jq -r '[(.auths // {}) | to_entries[] | select(.value.auth) | .key] | join(", ")' "$file" 2>/dev/null)"; then
    report_warn secrets.docker "Docker registry logins kept in the Keychain" "~/.docker/config.json is not valid JSON" \
      "Fix or remove ~/.docker/config.json"
    return
  fi
  creds_store="$(jq -r '.credsStore // ""' "$file")"
  if [[ -n "$registries" ]]; then
    report_fail secrets.docker "Docker registry logins kept in the Keychain" "plaintext logins for: $registries" \
      "Set \"credsStore\": \"osxkeychain\" in ~/.docker/config.json, then docker logout and login again"
  elif [[ -z "$creds_store" ]]; then
    report_warn secrets.docker "Docker registry logins kept in the Keychain" "no credsStore: the next login is saved in plaintext" \
      "Set \"credsStore\": \"osxkeychain\" in ~/.docker/config.json"
  else
    report_pass secrets.docker "Docker registry logins kept in the Keychain" "credsStore: $creds_store"
  fi
}

check_secrets_maven() {
  local file="$HOME/.m2/settings.xml" lines
  lines="$(grep -nE '<password>[^{$<][^<]*</password>' "$file" 2>/dev/null | cut -d: -f1 | join_lines)"
  if [[ -z "$lines" ]]; then
    report_pass secrets.maven "Maven passwords encrypted"
  else
    report_fail secrets.maven "Maven passwords encrypted" "plaintext <password> in ~/.m2/settings.xml on line $lines" \
      "Encrypt them (mvn --encrypt-password) or read them from environment variables: \${env.NAME}"
  fi
}

check_secrets_kube() {
  local files
  files="$(kubeconfigs_with_static_credentials | join_lines)"
  if [[ -z "$files" ]]; then
    report_pass secrets.kube "No long-lived Kubernetes credentials"
  else
    report_warn secrets.kube "No long-lived Kubernetes credentials" "static tokens or keys in $files" \
      "Use an exec credential plugin (kubelogin, aws eks get-token, gke-gcloud-auth-plugin) instead"
  fi
}

kubeconfigs_with_static_credentials() {
  local file
  echo "${KUBECONFIG:-$HOME/.kube/config}" | tr ':' '\n' | while IFS= read -r file; do
    if grep -qE '^[[:space:]]*(token|client-key-data|password):' "$file" 2>/dev/null; then
      tilde_path "$file"
    fi
  done
}

check_secrets_terraform() {
  if [[ -f "$HOME/.terraform.d/credentials.tfrc.json" ]]; then
    report_warn secrets.terraform "No plaintext OpenTofu/Terraform registry tokens" "~/.terraform.d/credentials.tfrc.json holds API tokens" \
      "Use a credentials helper or TF_TOKEN_<host> variables read from the Keychain"
  else
    report_pass secrets.terraform "No plaintext OpenTofu/Terraform registry tokens"
  fi
}

check_secrets_gh() {
  if grep -q 'oauth_token:' "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
    report_warn secrets.gh "GitHub CLI token kept in the Keychain" "~/.config/gh/hosts.yml holds a token" \
      "Run: gh auth logout && gh auth login (stores the token in the Keychain)"
  else
    report_pass secrets.gh "GitHub CLI token kept in the Keychain"
  fi
}

check_secrets_repos() {
  if [[ -z "$SCAN_REPOS_DIR" ]]; then
    report_skip secrets.repos "No secrets in git repositories" "pass --scan-repos DIR to scan with gitleaks"
    return
  fi
  if ! has_command gitleaks; then
    report_skip secrets.repos "No secrets in git repositories" "gitleaks not installed (brew install gitleaks)"
    return
  fi
  local findings
  findings="$(repo_secret_findings | join_lines)"
  if [[ -z "$findings" ]]; then
    report_pass secrets.repos "No secrets in git repositories" "scanned $(tilde_path "$SCAN_REPOS_DIR")"
  else
    report_fail secrets.repos "No secrets in git repositories" "$findings" \
      "Inspect with: gitleaks git --redact -v REPO; rotate every real secret, then rewrite history if needed"
  fi
}

# Prints "repo: N findings" for each repository with gitleaks findings, current files and history.
repo_secret_findings() {
  local repo report count
  report="$(mktemp -t gitleaks)"
  find "$SCAN_REPOS_DIR" -maxdepth 5 -type d -name .git -prune 2>/dev/null | sort | while IFS= read -r repo; do
    repo="$(dirname "$repo")"
    gitleaks git "$repo" --no-banner --redact --exit-code 0 --log-level error \
      --report-format json --report-path "$report" >/dev/null 2>&1 || continue
    count="$(jq length "$report" 2>/dev/null)" || count=0
    [[ "$count" -eq 0 ]] || echo "$(tilde_path "$repo"): $count finding(s)"
  done
  rm -f "$report"
}
