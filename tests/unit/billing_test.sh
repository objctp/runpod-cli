#!/usr/bin/env bash
# Unit tests for lib/billing.sh — the shared billing window-flag seam.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/billing.sh"
  eval "$_opts"
}

function set_up() {
  BW_WINDOW=()
}

# Main-shell call: rp::billing_window_query assigns via nameref and exits from
# the caller's shell on a usage error, so a $(...) capture would hide it.
function test_window_query_is_empty_when_no_flags_given() {
  rp::args_parse
  rp::billing_window_query BW_WINDOW "rp billing"
  assert_equals "0" "${#BW_WINDOW[@]}"
}

function test_window_query_carries_start_end_and_bucket() {
  rp::args_parse --start 2026-07-01T00:00:00Z --end 2026-08-01T00:00:00Z --bucket-size day
  rp::billing_window_query BW_WINDOW "rp billing"
  assert_equals "?startTime=2026-07-01T00:00:00Z&endTime=2026-08-01T00:00:00Z&bucketSize=day" \
    "$(rp::query_params "${BW_WINDOW[@]}")"
}

function test_window_query_carries_last_n() {
  rp::args_parse --last-n 7
  rp::billing_window_query BW_WINDOW "rp billing"
  assert_equals "?lastN=7" "$(rp::query_params "${BW_WINDOW[@]}")"
}

function test_window_query_rejects_last_n_with_start() {
  rp::args_parse --last-n 1 --start 2026-07-01T00:00:00Z
  (rp::billing_window_query BW_WINDOW "rp billing" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_window_query_rejects_last_n_zero() {
  rp::args_parse --last-n 0
  (rp::billing_window_query BW_WINDOW "rp billing" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_window_query_rejects_non_integer_last_n() {
  rp::args_parse --last-n soon
  (rp::billing_window_query BW_WINDOW "rp billing" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_window_query_rejects_unknown_bucket_size() {
  rp::args_parse --bucket-size fortnight
  (rp::billing_window_query BW_WINDOW "rp billing" >/dev/null 2>&1)
  assert_exit_code 2
}
