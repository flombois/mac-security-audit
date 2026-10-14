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

  [[ "$(result_of network.firewall)" == pass ]]
}

@test "firewall off fails" {
  stub_command socketfilterfw "Firewall is disabled. (State = 0)"

  run check_network_firewall

  [[ "$(result_of network.firewall)" == "fail high" ]]
}

@test "stealth mode on passes" {
  stub_command socketfilterfw "Firewall stealth mode is on"

  run check_network_stealth_mode

  [[ "$(result_of network.stealth-mode)" == pass ]]
}

@test "stealth mode off warns" {
  stub_command socketfilterfw "Firewall stealth mode is off"

  run check_network_stealth_mode

  [[ "$(result_of network.stealth-mode)" == "fail low" ]]
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

  [[ "$(result_of network.sharing-services)" == pass ]]
}

@test "AirPlay Receiver listening warns" {
  given_listeners "*.5000" ControlCenter

  run check_network_airplay_receiver

  [[ "$(result_of network.airplay-receiver)" == "fail low" ]]
}

@test "dev server on port 5000 is not mistaken for AirPlay" {
  given_listeners "*.5000" python3

  run check_network_airplay_receiver

  [[ "$(result_of network.airplay-receiver)" == pass ]]
}

@test "dev servers reachable from the network warn and are named" {
  stub_command netstat "$(cat "$FIXTURES_DIR/netstat-listeners.txt")"

  run check_network_exposed_listeners

  [[ "$(detail_of network.exposed-listeners)" == "java on *:8080, node server on 192.168.2.7:3000 (Next.js/Nuxt/Remix)" ]]
}

@test "a Vite dev server reachable from the network is named" {
  given_listeners "*.5173" node

  run check_network_exposed_listeners

  [[ "$(detail_of network.exposed-listeners)" == "node on *:5173 (Vite/VitePress)" ]]
}

@test "listeners macOS opens by design pass" {
  given_listeners "*.53375" rapportd "fe80::f432:c2ff:.53598" remoted 127.0.0.1.63342 idea

  run check_network_exposed_listeners

  [[ "$(result_of network.exposed-listeners)" == pass ]]
}

@test "AirDrop for everyone warns" {
  stub_command defaults Everyone

  run check_network_airdrop

  [[ "$(result_of network.airdrop)" == "fail low" ]]
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

  [[ "$(result_of network.docker-ports)" == pass ]]
}

@test "Docker not running is skipped" {
  stub_command docker "Cannot connect to the Docker daemon" 1

  run check_network_docker_ports

  [[ "$(result_of network.docker-ports)" == skipped ]]
}

@test "started Homebrew services are listed as local servers" {
  stub_command brew "$(printf 'Name          Status  User    File\npostgresql@16 started someone ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist\nredis         none')"

  run check_network_local_servers

  [[ "$(detail_of network.local-servers)" == "Homebrew services: postgresql@16" ]]
}

@test "remote access tool warns" {
  given_app TeamViewer com.teamviewer.TeamViewer 15.70

  run check_network_remote_access

  [[ "$(detail_of network.remote-access)" == "TeamViewer 15.70" ]]
}

@test "no remote access tool passes" {
  INVENTORY_CATALOGUE="$BATS_TEST_TMPDIR/catalogue.tsv"
  printf 'remote-access\tAnyDesk\tapp:com.philandro.anydesk\n' >"$INVENTORY_CATALOGUE"

  run check_network_remote_access

  [[ "$(result_of network.remote-access)" == pass ]]
}

@test "running tunnel warns" {
  stub_script pgrep <<'EOF'
[[ "$2" == ngrok ]]
EOF

  run check_network_running_tunnels

  [[ "$(detail_of network.running-tunnels)" == "running: ngrok" ]]
}

@test "no running tunnel passes" {
  stub_command pgrep "" 1

  run check_network_running_tunnels

  [[ "$(result_of network.running-tunnels)" == pass ]]
}

# Usage: given_trust_settings user_fixture admin_fixture ("" for none)
given_trust_settings() {
  stub_script security <<EOF
fixture="$FIXTURES_DIR/\$([[ "\$2" == -d ]] && echo "$2" || echo "$1")"
[[ -f "\$fixture" ]] || { echo "SecTrustSettingsCopyCertificates: No Trust Settings were found." >&2; exit 1; }
cat "\$fixture"
EOF
}

@test "trusted HTTPS proxy certificate warns" {
  given_trust_settings dump-trust-settings-proxy.txt dump-trust-settings-corporate.txt

  run check_network_trusted_certificates

  [[ "$(detail_of network.trusted-certificates)" == "Charles Proxy CA (13 Oct 2026, example-mac)" ]]
}

@test "other trusted certificates are listed" {
  given_trust_settings "" dump-trust-settings-corporate.txt

  run check_network_trusted_certificates

  [[ "$(detail_of network.trusted-certificates)" == "Example Corp Root CA" ]]
}

@test "no certificates trusted by hand passes" {
  given_trust_settings "" ""

  run check_network_trusted_certificates

  [[ "$(result_of network.trusted-certificates)" == pass ]]
}
