#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/inventory.sh
  INVENTORY_CATALOGUE="$BATS_TEST_TMPDIR/catalogue.tsv"
  echo "# category	name	finder" >"$INVENTORY_CATALOGUE"
}

# Usage: given_catalogue_row category name finder
given_catalogue_row() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$INVENTORY_CATALOGUE"
}

@test "a bundle id glob lists every matching app with its version" {
  given_catalogue_row ides JetBrains 'app:com.jetbrains.*'
  given_app "IntelliJ IDEA" com.jetbrains.intellij 2026.2.3
  given_app WebStorm com.jetbrains.WebStorm 2026.2.1

  report_catalogue test.ides "IDEs" ides

  [[ "$(detail_of test.ides)" == "IntelliJ IDEA 2026.2.3, WebStorm 2026.2.1" ]]
}

@test "an app without a version is listed by name" {
  given_catalogue_row browsers Arc app:company.thebrowser.Browser
  given_app Arc company.thebrowser.Browser

  report_catalogue test.browsers "Browsers" browsers

  [[ "$(detail_of test.browsers)" == "Arc" ]]
}

@test "an app name glob finds apps by file name" {
  given_catalogue_row vpn "Cisco Secure Client" 'name:Cisco Secure Client*'
  given_app "Cisco Secure Client - Socket Filter" com.example.unknown 5.1

  report_catalogue test.vpn "VPNs" vpn

  [[ "$(detail_of test.vpn)" == "Cisco Secure Client - Socket Filter 5.1" ]]
}

@test "apps in a vendor folder are found" {
  given_catalogue_row security Sophos 'app:com.sophos.*'
  given_app "Sophos Endpoint" com.sophos.endpoint 10.0 "$INVENTORY_APP_DIRS/Sophos"

  report_catalogue test.security "Security software" security

  [[ "$(detail_of test.security)" == "Sophos Endpoint 10.0" ]]
}

@test "installers and uninstallers are not listed" {
  given_catalogue_row security "Example Antivirus" 'app:com.example.antivirus.*'
  given_app "Example Antivirus Uninstaller" com.example.antivirus.uninstaller 1.0
  given_app SecurityNetworkInstallerApp com.example.antivirus.networkinstaller 1.0

  report_catalogue test.security "Security software" security

  [[ "$(detail_of test.security)" == "none found" ]]
}

@test "a command on PATH is listed by its catalogue name" {
  given_catalogue_row cloud "Example CLI" cmd:example-cli
  stub_command example-cli ""

  report_catalogue test.cloud "Cloud CLIs" cloud

  [[ "$(detail_of test.cloud)" == "Example CLI" ]]
}

@test "a path under ~ is found" {
  given_catalogue_row managers SDKMAN 'path:~/.sdkman'
  mkdir -p "$HOME/.sdkman"

  report_catalogue test.managers "Package managers" managers

  [[ "$(detail_of test.managers)" == "SDKMAN" ]]
}

@test "software found twice is listed once" {
  given_catalogue_row containers Docker app:com.docker.docker
  given_catalogue_row containers Docker cmd:docker
  given_app Docker com.docker.docker 4.82.0
  stub_command docker ""

  report_catalogue test.containers "Containers" containers

  [[ "$(detail_of test.containers)" == "Docker 4.82.0" ]]
}

@test "nothing installed says none found" {
  given_catalogue_row browsers Arc app:company.thebrowser.Browser

  report_catalogue test.browsers "Browsers" browsers

  [[ "$(detail_of test.browsers)" == "none found" ]]
}

@test "other apps leave out Apple and catalogued apps" {
  given_catalogue_row browsers "Google Chrome" app:com.google.Chrome
  given_app "Google Chrome" com.google.Chrome 155.0
  given_app Safari com.apple.Safari 26.6
  given_app Spotify com.spotify.client 1.3.4

  [[ "$(uncatalogued_apps)" == "Spotify 1.3.4" ]]
}
