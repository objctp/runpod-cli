#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/lib/paginate.sh"
  eval "$_opts"
}

PODS_BODY='{"pods":[{"id":"1"},{"id":"2"},{"id":"3"},{"id":"4"}]}'

function set_up() {
  OUT="$(mktemp)"
  # Double returns a 4-item wrapped list; capture the dispatched call too.
  CAP="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"$CAP"
    printf '%s' "$PODS_BODY"
  }
}

function tear_down() {
  rm -f "$OUT" "$CAP"
}

function run_list() {
  # $1 resource, remaining args are flags; --json forced so output is raw JSON.
  rp::args_parse --json "$@"
  rp::resource_list "$1" id >"$OUT"
}

function test_limit_caps_top_level_array() {
  run_list pod --limit 2
  assert_equals '[{"id":"1"},{"id":"2"}]' "$(<"$OUT")"
}

function test_cursor_offsets_into_array() {
  run_list pod --limit 2 --cursor 2
  assert_equals '[{"id":"3"},{"id":"4"}]' "$(<"$OUT")"
}

function test_cursor_past_end_yields_empty() {
  run_list pod --limit 2 --cursor 9
  assert_equals '[]' "$(<"$OUT")"
}

function test_jq_selects_fields() {
  run_list pod --jq 'map(.id)'
  assert_equals '["1","2","3","4"]' "$(<"$OUT")"
}

function test_jq_then_limit() {
  # --jq extracts the array; --limit then caps it (paginate runs after select).
  run_list pod --jq '.' --limit 2
  assert_equals '[{"id":"1"},{"id":"2"}]' "$(<"$OUT")"
}

function test_next_cursor_hint_to_stderr() {
  local err
  rp::args_parse --json --limit 2
  err="$(rp::resource_list pod id 2>&1 >/dev/null)"
  assert_contains "next cursor: 2" "$err"
}

function test_bad_limit_is_usage_error() {
  local out
  out="$(
    rp::args_parse --limit abc
    rp::resource_list pod id 2>&1
  )"
  assert_contains "--limit must be a positive integer" "$out"
}
