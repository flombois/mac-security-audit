# Verified HTTPS downloads; source it, don't run it.

HTTPS_TIMEOUT_SECONDS=10
HTTPS_MAX_BYTES=10M

# Usage: safe_https_call url output_file [check_command]
# Downloads url to output_file only when the answer is 2xx and check_command, if given, accepts
# the downloaded file (passed as its last argument); otherwise output_file is left as it was.
# curl checks the server certificate, its chain up to a trusted root and the host name, and
# -q skips ~/.curlrc, so no setting there can turn those checks off. Only https is allowed,
# redirects included, and answers stop at $HTTPS_MAX_BYTES.
safe_https_call() {
  local url="$1" output="$2" download status
  [[ "$url" == https://* ]] || return 1
  download="$(mktemp "$(dirname "$output")/.download.XXXXXX")" || return 1
  status="$(curl -q --silent --proto =https --proto-redir =https --tlsv1.2 --max-time "$HTTPS_TIMEOUT_SECONDS" \
    --max-filesize "$HTTPS_MAX_BYTES" --output "$download" --write-out '%{http_code}' "$url")" || status=failed
  if [[ "$status" == 2?? ]] && { [[ $# -lt 3 ]] || "${@:3}" "$download" >/dev/null 2>&1; }; then
    mv -f "$download" "$output"
  else
    rm -f "$download"
    return 1
  fi
}
