#!/usr/bin/env bats

load test_helper

setup() {
  setup_audit lib/runner.sh
  for check_file in "$ROOT_DIR"/checks/*.sh; do
    source "$check_file"
  done
}

# Prints the id of every queued check, without running them.
queued_ids() {
  local section
  run_check() { check_id "$2"; }
  run_root_check() { check_id "$2"; }
  for section in platform accounts network persistence secrets dev-tooling backup; do
    CHECK_SECTION="$section"
    "run_${section//-/_}_checks"
  done
}

# Prints every id the checks report under.
reported_ids() {
  grep -ohE 'report_[a-z]+ "?[a-z-]+\.[a-z0-9-]+' "$ROOT_DIR"/checks/*.sh | awk '{ print $2 }' | tr -d '"' | sort -u
}

@test "every check has its own id" {
  [[ -z "$(queued_ids | sort | uniq -d)" ]]
}

@test "checks report under their own id only" {
  [[ "$(queued_ids | sort)" == "$(reported_ids)" ]]
}

# Prints the ids of the checks that can fail or need a review.
ids_to_explain() {
  grep -ohE 'report_(fail|manual) "?[a-z-]+\.[a-z0-9-]+' "$ROOT_DIR"/checks/*.sh | awk '{ print $2 }' | tr -d '"' | sort -u
}

@test "every check that can fail or needs a review says why it matters" {
  [[ "$(ids_to_explain)" == "$(jq -r 'keys[]' "$ROOT_DIR/data/risks.json" | sort)" ]]
}

@test "every explanation has a risk and an impact" {
  jq -e 'all(.[]; (.risk | length > 0) and (.impact | length > 0))' "$ROOT_DIR/data/risks.json"
}
