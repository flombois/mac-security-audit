#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/https.sh
  TARGET="$BATS_TEST_TMPDIR/target"
  echo "old" >"$TARGET"
}

# Usage: given_answer http_status body [curl_exit_status]; curl records its arguments and answers so.
given_answer() {
  printf '%s' "$2" >"$STUB_DIR/curl.body"
  stub_script curl <<STUB
echo "\$*" >>"$STUB_DIR/curl.calls"
while [[ \$# -gt 0 ]]; do
  [[ "\$1" != --output ]] || cp "$STUB_DIR/curl.body" "\$2"
  shift
done
printf '%s' "$1"
exit ${3:-0}
STUB
}

curl_calls() {
  [[ ! -e "$STUB_DIR/curl.calls" ]] || cat "$STUB_DIR/curl.calls"
}

@test "a 2xx answer replaces the file" {
  given_answer 200 "new"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$status" -eq 0 && "$(cat "$TARGET")" == new ]]
}

@test "an error answer keeps the file" {
  given_answer 404 "not found"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$status" -ne 0 && "$(cat "$TARGET")" == old ]]
}

@test "a failed transfer keeps the file, even after a 2xx status" {
  given_answer 200 "half" 18

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$status" -ne 0 && "$(cat "$TARGET")" == old ]]
}

@test "a download the check command rejects keeps the file" {
  given_answer 200 "<html>maintenance</html>"

  run safe_https_call https://example.com/data "$TARGET" jq -e .

  [[ "$status" -ne 0 && "$(cat "$TARGET")" == old ]]
}

@test "a download the check command accepts replaces the file" {
  given_answer 200 '{"ok": true}'

  run safe_https_call https://example.com/data "$TARGET" jq -e .ok

  [[ "$(jq -r .ok "$TARGET")" == true ]]
}

@test "no download is left behind" {
  given_answer 500 "error"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$(ls -A "$BATS_TEST_TMPDIR" | grep -c download)" -eq 0 ]]
}

@test "a plain http url is refused without a call" {
  given_answer 200 "new"

  run safe_https_call http://example.com/data "$TARGET"

  [[ "$status" -ne 0 && -z "$(curl_calls)" ]]
}

@test "curl ignores ~/.curlrc and allows https only, redirects included" {
  given_answer 200 "new"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$(curl_calls)" == "-q "*"--proto =https --proto-redir =https --tlsv1.2 "* ]]
}

@test "the answer's size is capped" {
  given_answer 200 "new"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$(curl_calls)" == *" --max-filesize $HTTPS_MAX_BYTES "* ]]
}

@test "certificate checks are never turned off" {
  given_answer 200 "new"

  run safe_https_call https://example.com/data "$TARGET"

  [[ "$(curl_calls)" != *" -k "* && "$(curl_calls)" != *--insecure* ]]
}
