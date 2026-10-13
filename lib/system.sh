# Command paths and system helpers; source it, don't run it.
# Paths are environment overridable so tests can point them at stubs and fixtures.

SOCKETFILTERFW="${SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
SUDO_LOCAL_FILE="${SUDO_LOCAL_FILE:-/etc/pam.d/sudo_local}"
SYSTEM_LAUNCH_DIRS="${SYSTEM_LAUNCH_DIRS:-/Library/LaunchAgents /Library/LaunchDaemons}"

has_command() {
  command -v "$1" >/dev/null 2>&1
}

# True when sudo can run without prompting (credentials cached by `sudo -v`).
sudo_available() {
  sudo -n true >/dev/null 2>&1
}

# Prints a path with $HOME shortened to ~.
tilde_path() {
  case "$1" in
    "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
    *) echo "$1" ;;
  esac
}

# Prints the non-empty lines of stdin joined by ", ".
join_lines() {
  sed '/^$/d' | paste -sd ',' - | sed 's/,/, /g'
}

# Prints the octal permission bits of a file, e.g. 600.
file_mode() {
  stat -f '%Lp' "$1"
}

# Prints the age in whole days of a date given as "YYYY-MM-DD HH:MM:SS".
days_since() {
  local then_seconds now_seconds
  then_seconds="$(date -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s 2>/dev/null)" || return 1
  now_seconds="$(date +%s)"
  echo $(((now_seconds - then_seconds) / 86400))
}

docker_running() {
  has_command docker && docker info >/dev/null 2>&1
}
