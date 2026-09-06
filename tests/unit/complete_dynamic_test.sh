#!/usr/bin/env bash
# rp::_rp_complete / rp::complete_refresh — dynamic value completion behind
# `rp _complete`. The transport is mocked; the cache dir and credentials dir
# point at throwaway temp dirs, so every case runs hermetic and offline.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  RP_CONFIG_HOME="$(mktemp -d)"
  RP_CREDS_DIR="$RP_CONFIG_HOME/credentials.d"
  RP_COST_CENTERS_FILE="$RP_CONFIG_HOME/cost-centers.json"
  export RP_CONFIG_HOME RP_CREDS_DIR RP_COST_CENTERS_FILE
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/paginate.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/lib/costcenter.sh"
  source "$RP_ROOT/lib/doc.sh"
  source "$RP_ROOT/lib/completion.sh"
  # The mock lands AFTER the real libs so it always wins (see
  # tests/unit/resource_test.sh for the sourcing-order rationale).
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"${CC_CAP:-/dev/null}"
    if [[ -n "${CC_FAIL:-}" ]]; then
      printf 'curl transport error: %s %s\n' "$1" "$2" >&2
      return 1
    fi
    printf '%s' "$CC_MOCK"
  }
  eval "$_opts"
}

function set_up() {
  rm -rf "$RP_CONFIG_HOME/completion"
  CC_CAP="$(mktemp)"
  CC_MOCK='[]'
  CC_FAIL=''
  RP_COMPLETION_SYNC_REFRESH=1
  rm -f "$RP_COST_CENTERS_FILE"
  mkdir -p "$RP_CREDS_DIR"
}

function tear_down() {
  rm -f "$CC_CAP"
}

# --- positional ids/names through the cache ---

function test_should_fetch_and_cache_on_cold_cache() {
  CC_MOCK='{"pods":[{"id":"p1","name":"alpha"},{"id":"p2"}]}'
  local out
  out="$(rp::complete pod list -)"
  assert_contains $'p1\talpha' "$out"
  assert_contains $'p2\t' "$out"
  assert_contains "GET /pods" "$(<"$CC_CAP")"
  [[ -f "$RP_CONFIG_HOME/completion/pod" ]]
  assert_equals "0" "$?"
}

function test_should_not_touch_network_when_cache_fresh() {
  CC_MOCK='{"pods":[{"id":"p1","name":"alpha"}]}'
  rp::complete pod list - >/dev/null
  : >"$CC_CAP"
  assert_contains $'p1\talpha' "$(rp::complete pod list -)"
  assert_not_contains "GET" "$(<"$CC_CAP")"
}

function test_should_serve_stale_cache_and_refresh() {
  CC_MOCK='{"pods":[{"id":"old","name":"stale"}]}'
  rp::complete pod list - >/dev/null
  # Backdate the fetch epoch past the TTL — the test cannot wait 5 minutes.
  sed -i '' -E '1s/^[0-9]+/1/' "$RP_CONFIG_HOME/completion/pod"
  CC_MOCK='{"pods":[{"id":"new","name":"fresh"}]}'
  : >"$CC_CAP"
  # RP_COMPLETION_SYNC_REFRESH=1 (set_up) makes the stale path refetch
  # foreground, so the printed output is the refreshed cache.
  assert_contains $'new\tfresh' "$(rp::complete pod list -)"
  assert_contains "GET /pods" "$(<"$CC_CAP")"
}

function test_should_stay_silent_when_cold_fetch_fails() {
  CC_FAIL=1
  local out
  out="$(rp::complete pod list -)"
  assert_equals "" "$out"
  [[ -f "$RP_CONFIG_HOME/completion/pod" ]]
  assert_not_equals "0" "$?"
}

function test_should_keep_old_cache_when_refresh_fails() {
  CC_MOCK='{"pods":[{"id":"p1","name":"alpha"}]}'
  rp::complete pod list - >/dev/null
  CC_FAIL=1
  assert_contains $'p1\talpha' "$(rp::complete pod list -)"
}

# --- local state candidates ---

function test_should_list_cost_center_names_for_flag() {
  rp::cc_create web >/dev/null
  assert_contains "web" "$(rp::complete pod create cost-center)"
}

function test_should_list_account_names_for_auth_positional() {
  : >"$RP_CREDS_DIR/work"
  : >"$RP_CREDS_DIR/personal"
  local out
  out="$(rp::complete auth switch -)"
  assert_contains "work" "$out"
  assert_contains "personal" "$out"
}

function test_should_stay_silent_for_unknown_targets() {
  assert_equals "" "$(rp::complete pod list bogus-flag)"
  assert_equals "" "$(rp::complete hub search -)"
}

function test_should_end_with_zero_even_when_silent() {
  rp::complete pod list bogus-flag
  assert_equals "0" "$?"
}
