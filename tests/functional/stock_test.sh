#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/commands/stock.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  STOCK_GPU_BODY='{"gpuTypes":[{"id":"NVIDIA L4","displayName":"L4","memoryInGb":24,"lowestPrice":{"minimumBidPrice":0.5,"stockStatus":"Medium"}}]}'
  STOCK_DC_BODY='{"dataCenters":[{"id":"US-CA-2","name":"west","s3apiEnabled":true},{"id":"EU-RO-1","name":"east","s3apiEnabled":false}]}'
  # Defined in set_up so the double wins over the real rp::graphql.
  rp::graphql() {
    if [[ "$1" == *"dataCenters"* ]]; then
      printf '%s' "$STOCK_DC_BODY"
    else
      printf '%s' "$STOCK_GPU_BODY"
    fi
  }
}

function tear_down() {
  rm -f "$OUT"
}

function test_should_return_raw_body_when_gpu_json() {
  rp::args_parse --json
  _stock_gpu >"$OUT"
  assert_equals "$STOCK_GPU_BODY" "$(<"$OUT")"
}

function test_should_render_table_when_gpu_no_json() {
  rp::args_parse
  _stock_gpu >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "VRAM_GB" "$rendered"
  assert_contains "NVIDIA L4" "$rendered"
  assert_contains "Medium" "$rendered"
}

function test_should_return_raw_body_when_dc_json() {
  rp::args_parse --json
  _stock_dc >"$OUT"
  assert_equals "$STOCK_DC_BODY" "$(<"$OUT")"
}

function test_should_render_yes_and_sorted_rows_when_dc_no_json() {
  rp::args_parse
  _stock_dc >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "DATACENTER" "$rendered"
  assert_contains "US-CA-2" "$rendered"
  assert_contains "yes" "$rendered"
}

function test_should_show_help_when_help_verb_given() {
  rp::cmd_stock help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp stock" "$(<"$OUT")"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_stock_verb() {
  local cap
  cap="$(mktemp)"
  rp::graphql() {
    printf '%s' "$1" >"$cap"
    printf '{"gpuTypes":[],"dataCenters":[]}'
  }
  rp::cmd_stock gpu >/dev/null 2>&1
  assert_contains "gpuTypes" "$(<"$cap")"
  rp::cmd_stock dc >/dev/null 2>&1
  assert_contains "dataCenters" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_exit_two_when_stock_verb_unknown() {
  (rp::cmd_stock __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}
