# Secrets at rest: credentials in plaintext files, SSH and GnuPG keys. Findings name the file and line, never the value.

SHELL_DOTFILES=".zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .npmrc .yarnrc .yarnrc.yml .bunfig.toml .pypirc .git-credentials"
# "name|extended regex"; the name is everything before the first "|".
SECRET_RULES=(
  "AWS access key|AKIA[0-9A-Z]{16}"
  "GitHub token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}"
  "GitLab token|glpat-[A-Za-z0-9_-]{20,}"
  "Slack token|xox[abprs]-[A-Za-z0-9-]{10,}"
  "Anthropic API key|sk-ant-[A-Za-z0-9_-]{20,}"
  "OpenAI API key|sk-(proj-)?[A-Za-z0-9]{20,}"
  "Private key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "npm token|_authToken\"?[[:space:]]*[=[:space:]][[:space:]]*\"?[^\$[:space:]\"]"
  "Yarn token|npmAuth(Token|Ident):[[:space:]]*[\"']?[^\"'\$[:space:]]"
  "Registry token|(^|[{,[:space:]])token[[:space:]]*=[[:space:]]*[\"'][^\"'\$]"
  "Password in URL|://[^/:@[:space:]]+:[^/@[:space:]\$]+@"
  "Hard-coded secret variable|[A-Z_]*(PASSWORD|SECRET|TOKEN|API_KEY|APIKEY|ACCESS_KEY)[A-Z_]*=[\"']?[^\"'\$({[:space:]][^\"'[:space:]]{7,}"
)
RSA_MIN_BITS=3072
# Files where CLIs keep their login: "name<TAB>file under ~<TAB>regex of the line that holds a token"
CLI_LOGIN_FILES="Vercel	~/Library/Application Support/com.vercel.cli/auth.json	\"token\"
Vercel	~/.vercel/auth.json	\"token\"
Netlify	~/Library/Preferences/netlify/config.json	\"token\"
Netlify	~/.netlify/config.json	\"token\"
Firebase	~/.config/configstore/firebase-tools.json	\"refresh_token\"
Wrangler	~/Library/Preferences/.wrangler/config/default.toml	(oauth|api)_token
Wrangler	~/.wrangler/config/default.toml	(oauth|api)_token
Expo	~/.expo/state.json	\"sessionSecret\"
Supabase	~/.supabase/access-token	.
Fly.io	~/.fly/config.yml	access_token
Railway	~/.railway/config.json	\"token\"
Sentry	~/.sentryclirc	^[[:space:]]*token[[:space:]]*="
# Folders where altool and fastlane look for App Store Connect API keys
APP_STORE_KEY_DIRS="~/.appstoreconnect/private_keys ~/private_keys ~/.private_keys"

run_secrets_checks() {
  run_check "shell dotfiles for secrets" check_secrets_dotfiles
  run_check "~/.netrc" check_secrets_netrc
  run_check "AWS credentials" check_secrets_aws
  run_check "Docker registry logins" check_secrets_docker
  run_check "Maven passwords" check_secrets_maven
  run_check "Gradle passwords" check_secrets_gradle
  run_check "kubeconfig credentials" check_secrets_kube
  run_check "OpenTofu/Terraform tokens" check_secrets_terraform
  run_check "GitHub CLI token" check_secrets_gh
  run_check "CLI logins" check_secrets_cli_logins
  run_check "~/.ssh permissions" check_secrets_ssh_dir
  run_check "SSH key permissions" check_secrets_ssh_key_permissions
  run_check "SSH key passphrases" check_secrets_ssh_key_passphrases
  run_check "SSH key strength" check_secrets_ssh_key_strength
  run_check "SSH agent forwarding" check_secrets_ssh_agent_forwarding
  run_check "authorized SSH keys" check_secrets_ssh_authorized_keys
  run_check "GnuPG permissions" check_secrets_gnupg_dir
  run_check "password managers" check_secrets_password_managers
}

check_secrets_dotfiles() {
  local findings
  findings="$(dotfile_secret_findings | join_lines)"
  if [[ -z "$findings" ]]; then
    report_pass secrets.dotfiles "No secrets in shell and tool dotfiles"
  else
    report_fail secrets.dotfiles high "No secrets in shell and tool dotfiles" "$findings" \
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
    report_fail secrets.netrc high "No passwords in ~/.netrc" "password on line $lines" \
      "Remove the passwords; use a credential helper or token from the Keychain"
  fi
}

check_secrets_aws() {
  local file="$HOME/.aws/credentials" profiles
  profiles="$(grep -cE '^[[:space:]]*aws_secret_access_key' "$file" 2>/dev/null)" || profiles=0
  if [[ "$profiles" -eq 0 ]]; then
    report_pass secrets.aws "No static AWS keys"
  else
    report_fail secrets.aws medium "No static AWS keys" "$profiles profile(s) in ~/.aws/credentials hold access keys" \
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
    report_error secrets.docker "Docker registry logins kept in the Keychain" "~/.docker/config.json is not valid JSON"
    return
  fi
  creds_store="$(jq -r '.credsStore // ""' "$file")"
  if [[ -n "$registries" ]]; then
    report_fail secrets.docker high "Docker registry logins kept in the Keychain" "plaintext logins for: $registries" \
      "Set \"credsStore\": \"osxkeychain\" in ~/.docker/config.json, then docker logout and login again"
  elif [[ -z "$creds_store" ]]; then
    report_fail secrets.docker low "Docker registry logins kept in the Keychain" "no credsStore: the next login is saved in plaintext" \
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
    report_fail secrets.maven high "Maven passwords encrypted" "plaintext <password> in ~/.m2/settings.xml on line $lines" \
      "Encrypt them (mvn --encrypt-password) or read them from environment variables: \${env.NAME}"
  fi
}

# gradle.properties can't read environment variables, so any value there is plaintext.
check_secrets_gradle() {
  local file="${GRADLE_USER_HOME:-$HOME/.gradle}/gradle.properties" lines
  lines="$(grep -niE '^[[:space:]]*[^#![:space:]=:]*(password|secret|token)[^[:space:]=:]*[[:space:]]*[=:][[:space:]]*[^[:space:]]' \
    "$file" 2>/dev/null | cut -d: -f1 | join_lines)"
  if [[ -z "$lines" ]]; then
    report_pass secrets.gradle "No plaintext passwords in Gradle properties"
  else
    report_fail secrets.gradle high "No plaintext passwords in Gradle properties" \
      "$(tilde_path "$file") on line $lines" \
      "Pass them as ORG_GRADLE_PROJECT_<name> variables read from the Keychain (security find-generic-password -w), and rotate them"
  fi
}

check_secrets_kube() {
  local files
  files="$(kubeconfigs_with_static_credentials | join_lines)"
  if [[ -z "$files" ]]; then
    report_pass secrets.kube "No long-lived Kubernetes credentials"
  else
    report_fail secrets.kube medium "No long-lived Kubernetes credentials" "static tokens or keys in $files" \
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
    report_fail secrets.terraform medium "No plaintext OpenTofu/Terraform registry tokens" "~/.terraform.d/credentials.tfrc.json holds API tokens" \
      "Use a credentials helper or TF_TOKEN_<host> variables read from the Keychain"
  else
    report_pass secrets.terraform "No plaintext OpenTofu/Terraform registry tokens"
  fi
}

check_secrets_gh() {
  if grep -q 'oauth_token:' "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
    report_fail secrets.gh medium "GitHub CLI token kept in the Keychain" "~/.config/gh/hosts.yml holds a token" \
      "Run: gh auth logout && gh auth login (stores the token in the Keychain)"
  else
    report_pass secrets.gh "GitHub CLI token kept in the Keychain"
  fi
}

check_secrets_cli_logins() {
  local logins exposed names
  logins="$(cli_logins)"
  exposed="$(echo "$logins" | awk -F'\t' 'NF && $3 !~ /00$/ { print $2 " (" $3 ")" }' | join_lines)"
  names="$(echo "$logins" | awk -F'\t' 'NF && !seen[$1]++ { print $1 }' | join_lines)"
  if [[ -n "$exposed" ]]; then
    report_fail secrets.cli-logins medium "CLI logins only readable by you" "readable by others: $exposed" \
      "Run: chmod 600 on each file; log out of the CLIs you no longer use"
  else
    report_pass secrets.cli-logins "CLI logins only readable by you" "${names:-none found}"
  fi
}

# Prints "name<TAB>~/file<TAB>mode" for each CLI login and App Store Connect key on disk; never reads a value.
cli_logins() {
  local name file pattern folder key
  echo "$CLI_LOGIN_FILES" | while IFS=$'\t' read -r name file pattern; do
    file="$(expand_tilde "$file")"
    grep -qE -- "$pattern" "$file" 2>/dev/null || continue
    printf '%s\t%s\t%s\n' "$name" "$(tilde_path "$file")" "$(file_mode "$file")"
  done
  for folder in $APP_STORE_KEY_DIRS; do
    for key in "$(expand_tilde "$folder")"/AuthKey_*.p8; do
      [[ -f "$key" ]] || continue
      printf 'App Store Connect key\t%s\t%s\n' "$(tilde_path "$key")" "$(file_mode "$key")"
    done
  done
}

check_secrets_ssh_dir() {
  if [[ ! -d "$HOME/.ssh" ]]; then
    report_skip secrets.ssh-dir "~/.ssh only readable by you" "no ~/.ssh"
    return
  fi
  local mode
  mode="$(file_mode "$HOME/.ssh")"
  if [[ "$mode" == 700 ]]; then
    report_pass secrets.ssh-dir "~/.ssh only readable by you"
  else
    report_fail secrets.ssh-dir medium "~/.ssh only readable by you" "mode $mode" "Run: chmod 700 ~/.ssh"
  fi
}

check_secrets_ssh_key_permissions() {
  local keys
  keys="$(ssh_keys_readable_by_others | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass secrets.ssh-key-permissions "SSH private keys only readable by you"
  else
    report_fail secrets.ssh-key-permissions high "SSH private keys only readable by you" "$keys" \
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

check_secrets_ssh_key_passphrases() {
  local keys
  keys="$(ssh_private_keys | while IFS= read -r key; do
    # Deriving the public key with an empty passphrase only succeeds on unprotected keys.
    if ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
      tilde_path "$key"
    fi
  done | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass secrets.ssh-key-passphrases "SSH private keys protected by a passphrase"
  else
    report_fail secrets.ssh-key-passphrases high "SSH private keys protected by a passphrase" "no passphrase: $keys" \
      "Run: ssh-keygen -p -f KEY, and add 'UseKeychain yes' to ~/.ssh/config; or move keys to Secretive / 1Password"
  fi
}

check_secrets_ssh_key_strength() {
  local keys
  keys="$(ssh_private_keys | while IFS= read -r key; do
    ssh-keygen -l -f "$key" 2>/dev/null | awk -v key="$(tilde_path "$key")" -v min="$RSA_MIN_BITS" '
      $NF == "(DSA)" || ($NF == "(RSA)" && $1 < min) { print key " (" $1 "-bit " substr($NF, 2, length($NF) - 2) ")" }'
  done | join_lines)"
  if [[ -z "$keys" ]]; then
    report_pass secrets.ssh-key-strength "SSH keys use strong algorithms"
  else
    report_fail secrets.ssh-key-strength medium "SSH keys use strong algorithms" "$keys" \
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

check_secrets_ssh_agent_forwarding() {
  if awk '
      tolower($1) == "host" { host = $2; next }
      tolower($1) == "forwardagent" && tolower($2) == "yes" && (host == "" || host == "*") { found = 1 }
      END { exit !found }' "$HOME/.ssh/config" 2>/dev/null; then
    report_fail secrets.ssh-agent-forwarding medium "SSH agent not forwarded to every host" "ForwardAgent yes applies to all hosts" \
      "Enable ForwardAgent only under specific Host blocks, or use ProxyJump instead"
  else
    report_pass secrets.ssh-agent-forwarding "SSH agent not forwarded to every host"
  fi
}

check_secrets_ssh_authorized_keys() {
  local count
  count="$(grep -cvE '^[[:space:]]*(#|$)' "$HOME/.ssh/authorized_keys" 2>/dev/null)" || count=0
  if [[ "$count" -eq 0 ]]; then
    report_pass secrets.ssh-authorized-keys "No keys allowed to log in to this Mac"
  else
    report_fail secrets.ssh-authorized-keys medium "No keys allowed to log in to this Mac" \
      "$count key(s) in ~/.ssh/authorized_keys can log in when Remote Login is on" \
      "Remove keys you don't need"
  fi
}

check_secrets_gnupg_dir() {
  local dir="${GNUPGHOME:-$HOME/.gnupg}" mode
  if [[ ! -d "$dir" ]]; then
    report_skip secrets.gnupg-dir "GnuPG home only readable by you" "no $(tilde_path "$dir")"
    return
  fi
  mode="$(file_mode "$dir")"
  if [[ "$mode" == 700 ]]; then
    report_pass secrets.gnupg-dir "GnuPG home only readable by you"
  else
    report_fail secrets.gnupg-dir medium "GnuPG home only readable by you" "$(tilde_path "$dir") has mode $mode" \
      "Run: chmod -R go-rwx $(tilde_path "$dir")"
  fi
}

check_secrets_password_managers() {
  report_catalogue secrets.password-managers "Password managers" password-managers
}
