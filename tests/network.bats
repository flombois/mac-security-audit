#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit checks/30-network.sh
  SOCKETFILTERFW="$STUB_DIR/socketfilterfw"
}

# Usage: given_listeners "local address" process ...; pairs of netstat address and process name.
given_listeners() {
  local lines=""
  while [[ $# -gt 0 ]]; do
    lines+="$(printf 'tcp4  0  0  %-22s *.*  LISTEN  0  0  131072  131072  %s:42  00100 00000006' "$1" "$2")"$'\n'
    shift 2
  done
  stub_command netstat "$(head -2 "$FIXTURES_DIR/netstat-listeners.txt")"$'\n'"$lines"
}

@test "firewall on passes" {
  stub_command socketfilterfw "Firewall is enabled. (State = 1)"

  run check_network_firewall

  [[ "$(status_of network.firewall)" == pass ]]
}

@test "firewall off fails" {
  stub_command socketfilterfw "Firewall is disabled. (State = 0)"

  run check_network_firewall

  [[ "$(status_of network.firewall)" == fail ]]
}

@test "stealth mode on passes" {
  stub_command socketfilterfw "Firewall stealth mode is on"

  run check_network_stealth_mode

  [[ "$(status_of network.stealth-mode)" == pass ]]
}

@test "stealth mode off warns" {
  stub_command socketfilterfw "Firewall stealth mode is off"

  run check_network_stealth_mode

  [[ "$(status_of network.stealth-mode)" == warn ]]
}

@test "listener parsing keeps process names with spaces" {
  stub_command netstat "$(cat "$FIXTURES_DIR/netstat-listeners.txt")"

  run tcp_listeners

  [[ "$output" == *$'192.168.2.7\t3000\tnode server'* ]]
}

@test "SSH listening on all interfaces fails" {
  stub_command netstat "$(cat "$FIXTURES_DIR/netstat-listeners.txt")"

  run check_network_sharing_services

  [[ "$(detail_of network.sharing-services)" == "listening: Remote Login (SSH)" ]]
}

@test "SSH listening on localhost only passes" {
  given_listeners 127.0.0.1.22 sshd

  run check_network_sharing_services

  [[ "$(status_of network.sharing-services)" == pass ]]
}

@test "AirPlay Receiver listening warns" {
  given_listeners "*.5000" ControlCenter

  run check_network_airplay_receiver

  [[ "$(status_of network.airplay-receiver)" == warn ]]
}

@test "dev server on port 5000 is not mistaken for AirPlay" {
  given_listeners "*.5000" python3

  run check_network_airplay_receiver

  [[ "$(status_of network.airplay-receiver)" == pass ]]
}

@test "dev servers reachable from the network warn and are named" {
  stub_command netstat "$(cat "$FIXTURES_DIR/netstat-listeners.txt")"

  run check_network_exposed_listeners

  [[ "$(detail_of network.exposed-listeners)" == "java on *:8080, node server on 192.168.2.7:3000" ]]
}

@test "listeners macOS opens by design pass" {
  given_listeners "*.53375" rapportd "fe80::f432:c2ff:.53598" remoted 127.0.0.1.63342 idea

  run check_network_exposed_listeners

  [[ "$(status_of network.exposed-listeners)" == pass ]]
}

@test "AirDrop for everyone warns" {
  stub_command defaults Everyone

  run check_network_airdrop

  [[ "$(status_of network.airdrop)" == warn ]]
}

@test "AirDrop default setting passes" {
  stub_command defaults "The domain/default pair does not exist" 1

  run check_network_airdrop

  [[ "$(detail_of network.airdrop)" == "Contacts Only" ]]
}

@test "Docker port published on all interfaces warns" {
  stub_script docker <<'EOF'
[[ "$1" == ps ]] && printf 'db\t0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp\nweb\t127.0.0.1:8080->80/tcp\n'
exit 0
EOF

  run check_network_docker_ports

  [[ "$(detail_of network.docker-ports)" == "published on all interfaces: db" ]]
}

@test "Docker ports on localhost pass" {
  stub_script docker <<'EOF'
[[ "$1" == ps ]] && printf 'web\t127.0.0.1:8080->80/tcp\n'
exit 0
EOF

  run check_network_docker_ports

  [[ "$(status_of network.docker-ports)" == pass ]]
}

@test "Docker not running is skipped" {
  stub_command docker "Cannot connect to the Docker daemon" 1

  run check_network_docker_ports

  [[ "$(status_of network.docker-ports)" == skip ]]
}
