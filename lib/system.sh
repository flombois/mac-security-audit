# Command paths and system helpers; source it, don't run it.
# Paths are environment overridable so tests can point them at stubs and fixtures.

SOCKETFILTERFW="${SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
SUDO_LOCAL_FILE="${SUDO_LOCAL_FILE:-/etc/pam.d/sudo_local}"
SYSTEM_LAUNCH_DIRS="${SYSTEM_LAUNCH_DIRS:-/Library/LaunchAgents /Library/LaunchDaemons}"
INVENTORY_APP_DIRS="${INVENTORY_APP_DIRS:-/Applications $HOME/Applications}"
HOMEBREW_PREFIXES="${HOMEBREW_PREFIXES:-/opt/homebrew /usr/local}"
JAVA_VM_DIR="${JAVA_VM_DIR:-/Library/Java/JavaVirtualMachines}"
PYTHON_ORG_DIR="${PYTHON_ORG_DIR:-/Library/Frameworks/Python.framework/Versions}"
GO_INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local/go}"

has_command() {
  command -v "$1" >/dev/null 2>&1
}

# Asks the terminal itself, since inside $(…) stdout is a pipe; 80 when it can't tell
# (a terminal without a size reports 0).
terminal_width() {
  local size
  size="${COLUMNS:-$(stty size 2>/dev/null </dev/tty)}" || true
  size="${size##* }"
  if [[ "$size" =~ ^[0-9]+$ && "$size" -ge 20 ]]; then echo "$size"; else echo 80; fi
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

# Prints a path with a leading ~ replaced by $HOME.
expand_tilde() {
  case "$1" in
    "~" | "~/"*) echo "$HOME${1#"~"}" ;;
    *) echo "$1" ;;
  esac
}

# Prints the non-empty lines of stdin joined by ", ".
join_lines() {
  awk 'NF { printf "%s%s", (count++ ? ", " : ""), $0 } END { if (count) print "" }'
}

# Usage: label_items label, with items on stdin
# Prints "label: a, b", or nothing when there are no items.
label_items() {
  local items
  items="$(join_lines)"
  [[ -z "$items" ]] || echo "$1: $items"
}

# Prints the non-empty lines of stdin joined by "; ".
join_groups() {
  awk 'NF { printf "%s%s", (count++ ? "; " : ""), $0 } END { if (count) print "" }'
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
