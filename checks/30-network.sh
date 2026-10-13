# Network: firewall and services reachable from other machines.

# Apple daemons that listen on all interfaces by design (rapportd: Continuity and Handoff).
EXPECTED_WILDCARD_PROCESSES="rapportd"

run_network_checks() {
  check_network_firewall
  check_network_stealth_mode
  check_network_sharing_services
  check_network_airplay_receiver
  check_network_exposed_listeners
  check_network_airdrop
  check_network_docker_ports
}

check_network_firewall() {
  local output
  output="$("$SOCKETFILTERFW" --getglobalstate 2>&1)" || true
  if [[ "$output" == *"enabled"* ]]; then
    report_pass network.firewall "Application firewall on"
  else
    report_fail network.firewall "Application firewall on" "$output" \
      "System Settings › Network › Firewall: turn on"
  fi
}

check_network_stealth_mode() {
  local output
  output="$("$SOCKETFILTERFW" --getstealthmode 2>&1)" || true
  if [[ "$output" == *"stealth mode is on"* ]]; then
    report_pass network.stealth-mode "Firewall stealth mode on"
  else
    report_warn network.stealth-mode "Firewall stealth mode on" "$output" \
      "System Settings › Network › Firewall › Options: turn on 'Enable stealth mode'"
  fi
}

check_network_sharing_services() {
  local services
  services="$(exposed_listeners | while IFS=$'\t' read -r _ port _; do
    sharing_service_for_port "$port"
  done | sort -u | join_lines)"
  if [[ -z "$services" ]]; then
    report_pass network.sharing-services "No remote access sharing services listening"
  else
    report_fail network.sharing-services "No remote access sharing services listening" "listening: $services" \
      "System Settings › General › Sharing: turn off the services you don't use"
  fi
}

# Prints the macOS sharing service that listens on a port, or nothing.
sharing_service_for_port() {
  case "$1" in
    22) echo "Remote Login (SSH)" ;;
    445) echo "File Sharing (SMB)" ;;
    548) echo "File Sharing (AFP)" ;;
    3283) echo "Remote Management" ;;
    5900) echo "Screen Sharing" ;;
  esac
}

check_network_airplay_receiver() {
  if exposed_listeners | awk -F'\t' '($2 == 5000 || $2 == 7000) && $3 ~ /ControlCenter|AirPlay/ { found = 1 } END { exit !found }'; then
    report_warn network.airplay-receiver "AirPlay Receiver off" "ControlCenter listens on all interfaces (port 5000/7000)" \
      "System Settings › General › AirDrop & Handoff › AirPlay Receiver: turn off, or limit to Current User"
  else
    report_pass network.airplay-receiver "AirPlay Receiver off"
  fi
}

check_network_exposed_listeners() {
  local listeners
  listeners="$(exposed_listeners | while IFS=$'\t' read -r address port process; do
    is_known_listener "$port" "$process" || echo "${process:-unknown} on $address:$port"
  done | sort -u | join_lines)"
  if [[ -z "$listeners" ]]; then
    report_pass network.exposed-listeners "Dev servers only listen on localhost"
  else
    report_warn network.exposed-listeners "Dev servers only listen on localhost" "$listeners" \
      "Bind dev servers, databases and debuggers to 127.0.0.1 instead of all interfaces"
  fi
}

# True for listeners that another check already reports, or that macOS opens by design.
is_known_listener() {
  local port="$1" process="$2"
  [[ -n "$(sharing_service_for_port "$port")" ]] && return 0
  [[ "$process" == ControlCenter || "$process" == AirPlay* ]] && return 0
  [[ " $EXPECTED_WILDCARD_PROCESSES " == *" $process "* ]]
}

# Prints "address<TAB>port<TAB>process" for TCP listeners reachable from other machines.
exposed_listeners() {
  tcp_listeners | awk -F'\t' '$1 !~ /^(127\.|::1$|fe80:|localhost)/'
}

# Prints "address<TAB>port<TAB>process" for every TCP listener; "*" is all interfaces.
# netstat shows every user's sockets without root, unlike lsof.
tcp_listeners() {
  netstat -anv -p tcp 2>/dev/null | awk '
    $6 == "LISTEN" {
      process = ""
      for (i = 11; i <= NF; i++) {
        process = process (process == "" ? "" : " ") $i
        if ($i ~ /:[0-9]+$/) break
      }
      sub(/:[0-9]+$/, "", process)
      address = $4; sub(/\.[^.]*$/, "", address)
      port = $4; sub(/.*\./, "", port)
      print address "\t" port "\t" process
    }' | sort -u
}

check_network_airdrop() {
  local mode
  mode="$(defaults read com.apple.sharingd DiscoverableMode 2>/dev/null)" || mode="Contacts Only"
  if [[ "$mode" == Everyone ]]; then
    report_warn network.airdrop "AirDrop limited to contacts" "discoverable by everyone" \
      "System Settings › General › AirDrop & Handoff › AirDrop: Contacts Only"
  else
    report_pass network.airdrop "AirDrop limited to contacts" "$mode"
  fi
}

check_network_docker_ports() {
  if ! docker_running; then
    report_skip network.docker-ports "Docker ports bound to localhost" "Docker is not running"
    return
  fi
  local containers
  containers="$(docker ps --format $'{{.Names}}\t{{.Ports}}' 2>/dev/null \
    | awk -F'\t' '$2 ~ /(0\.0\.0\.0|\[::\]|:::):/ { print $1 }' | join_lines)"
  if [[ -z "$containers" ]]; then
    report_pass network.docker-ports "Docker ports bound to localhost"
  else
    report_warn network.docker-ports "Docker ports bound to localhost" "published on all interfaces: $containers" \
      "Publish ports as 127.0.0.1:HOST:CONTAINER, e.g. -p 127.0.0.1:5432:5432"
  fi
}
