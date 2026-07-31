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

# Main-shell routing so the serverless/volumes branches register coverage.
function test_should_route_serverless_and_volumes_verbs() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_billing serverless >/dev/null 2>&1
  assert_equals "GET /billing/serverless" "$(<"$cap")"
  rp::cmd_billing public-endpoints >/dev/null 2>&1
  assert_equals "GET /billing/endpoints" "$(<"$cap")"
  rp::cmd_billing clusters >/dev/null 2>&1
  assert_equals "GET /billing/clusters" "$(<"$cap")"
  rp::cmd_billing volumes >/dev/null 2>&1
  assert_equals "GET /billing/networkvolumes" "$(<"$cap")"
  rp::cmd_billing all >/dev/null 2>&1
  assert_equals "GET /billing" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_filter_serverless_billing_when_id_given() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_billing serverless e1 >/dev/null 2>&1
  assert_equals "GET /billing/serverless?serverlessId=e1" "$(<"$cap")"
  rm -f "$cap"
}

# Pre-rename behaviour: `billing endpoints` meant serverless spend. The alias
# keeps old scripts working, with a pointer at the two replacement verbs.
function test_should_route_deprecated_endpoints_verb_with_warning() {
  local cap err
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  err="$(rp::cmd_billing endpoints 2>&1 >/dev/null)"
  assert_equals "GET /billing/serverless" "$(<"$cap")"
  assert_contains "deprecated" "$err"
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
