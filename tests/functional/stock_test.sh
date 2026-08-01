#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/validate.sh"
  source "$RP_ROOT/commands/stock.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  STOCK_GPU_BODY='{"gpus":[{"id":"NVIDIA L4","name":"L4","memory":24,"price":{"secure":0.5},"availability":"Medium"}]}'
  STOCK_DC_BODY='{"dataCenters":[{"id":"US-KS-2","name":"US Kansas 2","region":"NORTH_AMERICA","globalNetwork":true,"networkVolumeTypes":["STANDARD","HIGH_PERFORMANCE"],"compliance":["SOC_2_TYPE_2"],"gpuAvailability":[{"id":"NVIDIA GeForce RTX 4090","name":"RTX 4090","availability":"HIGH"},{"id":"NVIDIA L4","name":"L4","availability":"NONE"}]},{"id":"EU-RO-1","name":"EU Romania 1","region":"EUROPE","globalNetwork":false,"networkVolumeTypes":["STANDARD"],"compliance":[],"gpuAvailability":[]}]}'
  _RP_S3_DCS=() # bust the cache so each test controls the S3 source
  # gpu is REST API v2; dc is now v2 too (S3 column comes from _s3_dcs). The S3
  # resolver defaults to offline (GraphQL unreachable -> snapshot); tests that
  # need a specific S3 set override _s3_dcs directly.
  rp::http() {
    if [[ "${2:-}" == *datacenters* ]]; then printf '%s' "$STOCK_DC_BODY"; else printf '%s' "$STOCK_GPU_BODY"; fi
  }
  rp::graphql_soft() { return 1; }
}

function tear_down() {
  rm -f "$OUT"
}

function test_should_return_raw_body_when_gpu_json() {
  rp::args_parse --json
  _stock_gpu >"$OUT"
  assert_equals "$(printf '%s' "$STOCK_GPU_BODY" | jq -c '.gpus')" "$(<"$OUT")"
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

function test_should_return_raw_array_when_dc_json() {
  rp::args_parse --json
  _stock_dc >"$OUT"
  assert_equals "$(printf '%s' "$STOCK_DC_BODY" | jq -c '.dataCenters')" "$(<"$OUT")"
}

function test_should_render_columns_and_s3_yes_when_dc_no_json() {
  _s3_dcs() { printf '%s\n' "US-KS-2"; } # control the S3 column without GraphQL
  rp::args_parse
  _stock_dc >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "DATACENTER" "$rendered"
  assert_contains "NAME" "$rendered"
  assert_contains "REGION" "$rendered"
  assert_contains "GPUS" "$rendered"
  assert_contains "S3_API" "$rendered"
  assert_contains "US-KS-2" "$rendered"
  assert_contains "US Kansas 2" "$rendered"
  assert_contains "NORTH_AMERICA" "$rendered"
  assert_contains "yes" "$rendered"
  # GPUS = 1 for US-KS-2 (4090 HIGH; L4 NONE excluded); 0 for EU-RO-1.
  assert_contains $'US-KS-2\tUS Kansas 2\tNORTH_AMERICA\t1\tyes' "$rendered"
  assert_contains $'EU-RO-1\tEU Romania 1\tEUROPE\t0\t' "$rendered"
}

function test_should_render_s3_column_via_fallback_when_graphql_down() {
  _RP_S3_DCS=()                    # force re-resolution
  rp::graphql_soft() { return 1; } # GraphQL unreachable -> snapshot
  rp::args_parse
  _stock_dc >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  # US-KS-2 is in the fallback snapshot, so its S3 column still populates.
  assert_contains $'US-KS-2\tUS Kansas 2\tNORTH_AMERICA\t1\tyes' "$rendered"
}

function test_should_show_help_when_help_verb_given() {
  rp::cmd_stock help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp stock" "$(<"$OUT")"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_stock_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '{"gpus":[]}'
  }
  rp::cmd_stock gpu >/dev/null 2>&1
  assert_contains "GET /catalog/gpus" "$(<"$cap")"
  rp::cmd_stock dc >/dev/null 2>&1
  assert_contains "GET /catalog/datacenters" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_exit_two_when_stock_verb_unknown() {
  (rp::cmd_stock __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}
