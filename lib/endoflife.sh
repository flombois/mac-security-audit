# End-of-life dates from the endoflife.date API, cached for a day; source it, don't run it.
# A cached file is replaced only by a 2xx answer that holds release data.
# Uses safe_https_call from lib/https.sh.

EOL_API="https://endoflife.date/api/v1/products"
# runtime:product pairs
EOL_PRODUCTS="node:nodejs java:eclipse-temurin python:python go:go rust:rust ruby:ruby"
EOL_CACHE_DIR="${EOL_CACHE_DIR:-$HOME/Library/Caches/mac-security-audit/endoflife}"
EOL_CACHE_MAX_AGE_MINUTES=1440
REFRESH_CACHE="${REFRESH_CACHE:-false}"
NO_CACHE="${NO_CACHE:-false}"

# With --no-cache, dates go to a throwaway folder in the run's temporary folder.
prepare_eol_cache() {
  [[ "$NO_CACHE" == true ]] || return 0
  EOL_CACHE_DIR="$(mktemp -d "${RUNNER_DIR:-${TMPDIR:-/tmp}}/endoflife.XXXXXX")"
}

# Fetches, at the same time, each product whose cache is missing, empty or older than a day,
# or every product with --refresh-cache.
refresh_eol_cache() {
  local pair product
  for pair in $EOL_PRODUCTS; do
    product="${pair#*:}"
    eol_cache_fresh "$product" || fetch_eol_product "$product" &
  done
  wait
}

eol_cache_fresh() {
  [[ "$REFRESH_CACHE" != true ]] &&
    [[ -n "$(find "$EOL_CACHE_DIR/$1.json" -size +0 -mmin -"$EOL_CACHE_MAX_AGE_MINUTES" 2>/dev/null)" ]]
}

fetch_eol_product() {
  mkdir -p "$EOL_CACHE_DIR" || return
  safe_https_call "$EOL_API/$1" "$EOL_CACHE_DIR/$1.json" jq -e '.result.releases | type == "array"'
}

# True when at least one product has cached dates.
has_eol_data() {
  local files=("$EOL_CACHE_DIR"/*.json)
  [[ -s "${files[0]}" ]]
}

# Prints the day the oldest cached file was fetched.
eol_data_date() {
  find "$EOL_CACHE_DIR" -name '*.json' -exec stat -f '%Sm' -t '%F' {} + 2>/dev/null | sort | head -1
}

# Usage: end_of_life runtime version; prints the end-of-life date, if endoflife.date has one.
# Anything but a YYYY-MM-DD date is ignored, as the answer comes from outside.
end_of_life() {
  local key product file
  key="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  product="$(eol_product "$key")"
  file="$EOL_CACHE_DIR/$product.json"
  [[ -n "$product" && -s "$file" ]] || return 0
  # Old Ruby cycles carry a patch number: 2.0 is "2.0.0".
  jq -r --arg cycle "$(release_cycle "$key" "$2")" \
    'first(.result.releases[] | select(.name == $cycle or (.name | startswith($cycle + ".")))) | .eolFrom
     | select(type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))' \
    "$file" 2>/dev/null
}

eol_product() {
  local pair
  for pair in $EOL_PRODUCTS; do
    [[ "${pair%%:*}" != "$1" ]] || echo "${pair#*:}"
  done
}

# Java and Node releases are major versions (Java 1.8 is 8); the others are major.minor.
release_cycle() {
  case "$1:$2" in
    java:1.*) echo "$2" | cut -d. -f2 ;;
    java:* | node:*) echo "${2%%.*}" ;;
    *) echo "$2" | cut -d. -f1-2 ;;
  esac
}
