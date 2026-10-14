# Network: firewall and services reachable from other machines.

# Apple daemons that listen on all interfaces by design (rapportd: Continuity and Handoff).
EXPECTED_WILDCARD_PROCESSES="rapportd"

TUNNEL_COMMANDS="ngrok cloudflared bore zrok"
# Root certificates that HTTPS debugging proxies create
PROXY_CA_PATTERN="Charles|Proxyman|mitmproxy|HTTP Toolkit|PortSwigger|Fiddler"

run_network_checks() {
  run_check "firewall" check_network_firewall
  run_check "firewall stealth mode" check_network_stealth_mode
  run_check "sharing services" check_network_sharing_services
  run_check "AirPlay Receiver" check_network_airplay_receiver
  run_check "listening ports" check_network_exposed_listeners
  run_check "AirDrop" check_network_airdrop
  run_check "Docker published ports" check_network_docker_ports
  run_check "remote access tools" check_network_remote_access
  run_check "VPNs and tunnels" check_network_vpn_tunnels
  run_check "running tunnels" check_network_running_tunnels
  run_check "HTTPS proxy tools" check_network_proxy_tools
  run_check "trusted root certificates" check_network_trusted_certificates
  run_check "local servers" check_network_local_servers
}

check_network_firewall() {
  local output
  output="$("$SOCKETFILTERFW" --getglobalstate 2>&1)" || true
  if [[ "$output" == *"enabled"* ]]; then
    report_pass network.firewall "Application firewall on"
  else
    report_fail network.firewall high "Application firewall on" "$output" \
      "System Settings › Network › Firewall: turn on"
  fi
}

check_network_stealth_mode() {
  local output
  output="$("$SOCKETFILTERFW" --getstealthmode 2>&1)" || true
  if [[ "$output" == *"stealth mode is on"* ]]; then
    report_pass network.stealth-mode "Firewall stealth mode on"
  else
    report_fail network.stealth-mode low "Firewall stealth mode on" "$output" \
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
    report_fail network.sharing-services high "No remote access sharing services listening" "listening: $services" \
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
    report_fail network.airplay-receiver low "AirPlay Receiver off" "ControlCenter listens on all interfaces (port 5000/7000)" \
      "System Settings › General › AirDrop & Handoff › AirPlay Receiver: turn off, or limit to Current User"
  else
    report_pass network.airplay-receiver "AirPlay Receiver off"
  fi
}

check_network_exposed_listeners() {
  local listeners
  listeners="$(exposed_listeners | while IFS=$'\t' read -r address port process; do
    is_known_listener "$port" "$process" || echo "${process:-unknown} on $address:$port$(dev_server_hint "$port" "$process")"
  done | sort -u | join_lines)"
  if [[ -z "$listeners" ]]; then
    report_pass network.exposed-listeners "Dev servers only listen on localhost"
  else
    report_fail network.exposed-listeners medium "Dev servers only listen on localhost" "$listeners" \
      "Bind dev servers, databases and debuggers to 127.0.0.1 instead of all interfaces; for Vite and VitePress, drop --host and server.host, for ng serve, drop --host 0.0.0.0"
  fi
}

# Usage: dev_server_hint port process
# Prints " (tool)" when a JavaScript runtime listens on a dev server's default port.
dev_server_hint() {
  local tool
  case "$2" in
    node* | bun | deno) ;;
    *) return 0 ;;
  esac
  case "$1" in
    5173 | 4173) tool="Vite/VitePress" ;;
    3000) tool="Next.js/Nuxt/Remix" ;;
    4200) tool="Angular" ;;
    8080) tool="Vue CLI/webpack" ;;
    8081) tool="React Native Metro" ;;
    4321) tool="Astro" ;;
    6006) tool="Storybook" ;;
    9229) tool="Node inspector" ;;
    *) return 0 ;;
  esac
  echo " ($tool)"
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
    report_fail network.airdrop low "AirDrop limited to contacts" "discoverable by everyone" \
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
    report_fail network.docker-ports medium "Docker ports bound to localhost" "published on all interfaces: $containers" \
      "Publish ports as 127.0.0.1:HOST:CONTAINER, e.g. -p 127.0.0.1:5432:5432"
  fi
}

check_network_vpn_tunnels() {
  report_catalogue network.vpn-tunnels "VPNs and tunnels" vpn-tunnels
}

check_network_proxy_tools() {
  report_catalogue network.proxy-tools "HTTPS proxy and traffic tools" proxy-tools
}

check_network_local_servers() {
  local servers
  servers="$({
    catalogue_matches local-servers | label_items apps
    started_brew_services | label_items "Homebrew services"
  } | join_groups)"
  report_pass network.local-servers "Local servers" "${servers:-none found}"
}

started_brew_services() {
  has_command brew || return 0
  brew services list 2>/dev/null | awk 'NR > 1 && $2 == "started" { print $1 }'
}

check_network_remote_access() {
  local tools
  tools="$(catalogue_matches remote-access | join_lines)"
  if [[ -n "$tools" ]]; then
    report_fail network.remote-access medium "No remote access tools installed" "$tools" \
      "Uninstall the ones you don't use; protect the others with two-factor sign-in and quit them when not needed"
  else
    report_pass network.remote-access "No remote access tools installed"
  fi
}

check_network_running_tunnels() {
  local command running=""
  for command in $TUNNEL_COMMANDS; do
    ! pgrep -x "$command" >/dev/null 2>&1 || running="$running${running:+, }$command"
  done
  if [[ -n "$running" ]]; then
    report_fail network.running-tunnels medium "No tunnel exposing a local service" "running: $running" \
      "Stop tunnels when you are done: anyone with their URL reaches the service behind them"
  else
    report_pass network.running-tunnels "No tunnel exposing a local service"
  fi
}

check_network_trusted_certificates() {
  local certificates proxy_cas
  certificates="$(hand_trusted_certificates)"
  proxy_cas="$(echo "$certificates" | grep -E "$PROXY_CA_PATTERN" | join_lines)"
  if [[ -n "$proxy_cas" ]]; then
    report_fail network.trusted-certificates medium "No HTTPS proxy root certificate trusted" "$proxy_cas" \
      "Keychain Access: delete it, or set it to 'Never Trust' between debugging sessions; its private key sits on disk"
  elif [[ -n "$certificates" ]]; then
    report_pass network.trusted-certificates "Root certificates trusted by hand" "$(echo "$certificates" | join_lines)"
  else
    report_pass network.trusted-certificates "No root certificates trusted by hand"
  fi
}

# Prints the certificates given custom trust, by you or an admin.
hand_trusted_certificates() {
  {
    security dump-trust-settings 2>/dev/null
    security dump-trust-settings -d 2>/dev/null
  } | sed -n 's/^Cert [0-9]*: //p' | sort -u
}
