#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/commands/billing.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  BILLING_BODY='{"data":[{"id":"p1","cost":1.5}]}'
  # Defined in set_up (after set_up_before_script sourced lib/http.sh) so the
  # double wins over the real rp::http — otherwise tests would hit the live API.
  rp::http() { printf '%s' "$BILLING_BODY"; }
}

function tear_down() {
  rm -f "$OUT"
}

function test_should_return_raw_body_when_json_flag_set() {
  rp::args_parse --json
  _billing /billing/pods >"$OUT"
  assert_equals "$BILLING_BODY" "$(<"$OUT")"
}

function test_should_pretty_print_when_no_json_flag() {
  rp::args_parse
  _billing /billing/pods >"$OUT"
  local rendered
  rendered="$(<"$OUT")"
  assert_contains '"data"' "$rendered"
  assert_contains '"cost"' "$rendered"
}

function test_should_dispatch_pods_verb_to_billing_endpoint() {
  rp::args_parse
  rp::cmd_billing pods >"$OUT" 2>/dev/null
  assert_contains '"data"' "$(<"$OUT")"
}

# Main-shell routing so the endpoints/volumes branches register coverage.
function test_should_route_endpoints_and_volumes_verbs() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_billing endpoints >/dev/null 2>&1
  assert_contains "GET /billing/serverless" "$(<"$cap")"
  rp::cmd_billing volumes >/dev/null 2>&1
  assert_contains "GET /billing/networkvolumes" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_show_help_when_help_verb_given() {
  rp::cmd_billing help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp billing" "$(<"$OUT")"
}

function test_should_exit_two_when_billing_verb_unknown() {
  (rp::cmd_billing __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}
