#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/validate.sh"
  source "$RP_ROOT/commands/stock.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  STOCK_GPU_BODY='{"gpus":[{"id":"NVIDIA L4","name":"L4","memory":24,"price":{"secure":0.5},"availability":"Medium"}]}'
  STOCK_CPU_BODY='{"cpus":[{"id":"cpu3c-2-4","name":"Compute-Optimized","group":"Gen 3","vcpu":{"min":2,"max":32},"ramGbPerVcpu":2.5,"price":{"securePerVcpu":0.04,"serverlessPerVcpu":0.03},"availability":"MEDIUM"},{"id":"cpu5c","name":"Compute-Optimized","group":"Gen 5","vcpu":{"min":2,"max":16},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.05,"serverlessPerVcpu":0.04}}]}'
  STOCK_DC_BODY='{"dataCenters":[{"id":"US-KS-2","name":"US Kansas 2","region":"NORTH_AMERICA","globalNetwork":true,"networkVolumeTypes":["STANDARD","HIGH_PERFORMANCE"],"compliance":["SOC_2_TYPE_2"],"gpuAvailability":[{"id":"NVIDIA GeForce RTX 4090","name":"RTX 4090","availability":"HIGH"},{"id":"NVIDIA L4","name":"L4","availability":"NONE"}]},{"id":"EU-RO-1","name":"EU Romania 1","region":"EUROPE","globalNetwork":false,"networkVolumeTypes":["STANDARD"],"compliance":[],"gpuAvailability":[]}]}'
  _RP_S3_DCS=() # bust the cache so each test controls the S3 source
  # gpu is REST API v2; dc is now v2 too (S3 column comes from _s3_dcs). The S3
  # resolver defaults to offline (GraphQL unreachable -> snapshot); tests that
  # need a specific S3 set override _s3_dcs directly.
  rp::http() {
    case "${2:-}" in
    *datacenters*) printf '%s' "$STOCK_DC_BODY" ;;
    *cpus*) printf '%s' "$STOCK_CPU_BODY" ;;
    *) printf '%s' "$STOCK_GPU_BODY" ;;
    esac
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

function test_should_default_query_unchanged_when_no_flags() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse
  _stock_gpu >/dev/null 2>&1
  assert_equals "GET /catalog/gpus?include=AVAILABILITY&product=POD,SERVERLESS" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_product_when_flag_given() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse --product CLUSTER
  _stock_gpu >/dev/null 2>&1
  assert_contains "product=CLUSTER" "$(<"$cap")"
  assert_not_contains "POD,SERVERLESS" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_cloud_when_flag_given() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse --cloud COMMUNITY
  _stock_gpu >/dev/null 2>&1
  assert_contains "cloud=COMMUNITY" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_min_cuda_when_flag_given() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse --min-cuda 12.1
  _stock_gpu >/dev/null 2>&1
  assert_contains "minCudaVersion=12.1" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_min_count_when_flag_given() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse --min-count 4
  _stock_gpu >/dev/null 2>&1
  assert_contains "count=4" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_all_filters_together() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$STOCK_GPU_BODY"
  }
  rp::args_parse --cloud SECURE --min-count 2 --min-cuda 12
  _stock_gpu >/dev/null 2>&1
  local path
  path="$(<"$cap")"
  assert_contains "include=AVAILABILITY" "$path"
  assert_contains "product=POD,SERVERLESS" "$path"
  assert_contains "cloud=SECURE" "$path"
  assert_contains "count=2" "$path"
  assert_contains "minCudaVersion=12" "$path"
  rm -f "$cap"
}

function test_should_exit_two_on_bad_cloud() {
  rp::http() { printf '%s' "$STOCK_GPU_BODY"; }
  (
    rp::args_parse --cloud BOGUS
    _stock_gpu >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_exit_two_on_bad_min_cuda() {
  rp::http() { printf '%s' "$STOCK_GPU_BODY"; }
  (
    rp::args_parse --min-cuda 12.x
    _stock_gpu >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_exit_two_on_min_count_floor() {
  rp::http() { printf '%s' "$STOCK_GPU_BODY"; }
  (
    rp::args_parse --min-count 0
    _stock_gpu >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_exit_two_on_min_count_non_integer() {
  rp::http() { printf '%s' "$STOCK_GPU_BODY"; }
  (
    rp::args_parse --min-count abc
    _stock_gpu >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_exit_two_on_min_count_negative() {
  rp::http() { printf '%s' "$STOCK_GPU_BODY"; }
  (
    rp::args_parse --min-count -5
    _stock_gpu >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_return_raw_array_when_cpus_json() {
  rp::args_parse --json
  _stock_cpus >"$OUT"
  assert_equals "$(printf '%s' "$STOCK_CPU_BODY" | jq -c '.cpus')" "$(<"$OUT")"
}

function test_should_render_table_when_cpus_no_json() {
  rp::args_parse
  _stock_cpus >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "RAM_GB_VCPU" "$rendered"
  assert_contains "SECURE_PRICE_VCPU" "$rendered"
  assert_contains "DATACENTERS" "$rendered"
  # VCPU is the min-max range; the second flavour has no availability, so STOCK is blank.
  assert_matches "cpu3c-2-4 +Compute-Optimized +Gen 3 +2-32 +2\.5 +0\.04 +MEDIUM" "$rendered"
  # cpu5c has no availability and no dataCenters in the fixture: STOCK and
  # DATACENTERS are both blank, so the row ends "0.05  " (trailing spaces).
  # (line-anchored, since grep -E $ matches end of each rendered row).
  assert_matches "cpu5c +Compute-Optimized +Gen 5 +2-16 +2 +0\.05 *$" "$rendered"
}

function test_should_filter_cpus_by_dc_in_table() {
  STOCK_CPU_BODY='{"cpus":[{"id":"cpu3c","name":"Compute-Optimized","group":"CPU3","vcpu":{"min":2,"max":32},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.03},"availability":"HIGH","dataCenters":[{"id":"EU-CZ-1"},{"id":"US-CA-2"},{"id":"US-MO-2"}]},{"id":"cpu5c","name":"Compute-Optimized","group":"CPU5","vcpu":{"min":2,"max":16},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.05},"availability":"HIGH","dataCenters":[{"id":"EU-RO-1"},{"id":"EUR-IS-1"}]}]}'
  rp::args_parse --dc US-CA-2
  _stock_cpus >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "cpu3c" "$rendered"
  assert_not_contains "cpu5c" "$rendered"
  # Column is truncated to two ids + "+N more".
  assert_matches "EU-CZ-1, US-CA-2 \+1 more" "$rendered"
}

function test_should_filter_cpus_by_dc_in_json() {
  STOCK_CPU_BODY='{"cpus":[{"id":"cpu3c","name":"Compute-Optimized","group":"CPU3","vcpu":{"min":2,"max":32},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.03},"availability":"HIGH","dataCenters":[{"id":"EU-CZ-1"},{"id":"US-CA-2"}]},{"id":"cpu5c","name":"Compute-Optimized","group":"CPU5","vcpu":{"min":2,"max":16},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.05},"availability":"HIGH","dataCenters":[{"id":"EU-RO-1"}]}]}'
  rp::args_parse --dc eu-ro-1 --json
  _stock_cpus >"$OUT" 2>/dev/null
  # Case-insensitive match; only cpu5c survives and keeps its full dataCenters array.
  local expected='[{"id":"cpu5c","name":"Compute-Optimized","group":"CPU5","vcpu":{"min":2,"max":16},"ramGbPerVcpu":2,"price":{"securePerVcpu":0.05},"availability":"HIGH","dataCenters":[{"id":"EU-RO-1"}]}]'
  assert_equals "$expected" "$(<"$OUT")"
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
  assert_contains "REGION" "$rendered"
  assert_contains "GLOBAL_NETWORK" "$rendered"
  assert_contains "COMPLIANCE" "$rendered"
  assert_contains "NETWORK_VOLUME_TYPES" "$rendered"
  assert_contains "GPUS" "$rendered"
  assert_contains "S3_API" "$rendered"
  assert_contains "US-KS-2" "$rendered"
  assert_contains "NORTH_AMERICA" "$rendered"
  assert_contains "yes" "$rendered"
  # GPUS = 1 for US-KS-2 (4090 HIGH; L4 NONE excluded); 0 for EU-RO-1.
  # S3_API yes, globalNetwork true, SOC_2_TYPE_2 compliance, both volume tiers.
  assert_matches "US-KS-2 +NORTH_AMERICA +1 +yes +yes +SOC_2_TYPE_2 +STANDARD, HIGH_PERFORMANCE" "$rendered"
  # EU-RO-1: not in the S3 set, not on global network, no compliance; only the
  # STANDARD volume tier is advertised.
  assert_matches "EU-RO-1 +EUROPE +0 +STANDARD *$" "$rendered"
}

function test_should_render_s3_column_via_fallback_when_graphql_down() {
  _RP_S3_DCS=()                    # force re-resolution
  rp::graphql_soft() { return 1; } # GraphQL unreachable -> snapshot
  rp::args_parse
  _stock_dc >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  # US-KS-2 is in the fallback snapshot, so its S3 column still populates.
  assert_matches "US-KS-2 +NORTH_AMERICA +1 +yes +yes +SOC_2_TYPE_2 +STANDARD, HIGH_PERFORMANCE" "$rendered"
}

function test_should_filter_dc_to_s3_enabled_when_s3_flag() {
  _s3_dcs() { printf '%s\n' "US-KS-2"; } # control the S3 column without GraphQL
  rp::args_parse --s3
  _stock_dc >"$OUT" 2>/dev/null
  assert_contains "US-KS-2" "$(<"$OUT")"
  assert_not_contains "EU-RO-1" "$(<"$OUT")"
}

function test_should_filter_dc_to_global_network_when_global_flag() {
  rp::args_parse --global-network
  _stock_dc >"$OUT" 2>/dev/null
  assert_contains "US-KS-2" "$(<"$OUT")"
  assert_not_contains "EU-RO-1" "$(<"$OUT")"
}

function test_should_filter_dc_to_volume_type_when_volume_type_flag() {
  rp::args_parse --volume-type HIGH_PERFORMANCE
  _stock_dc >"$OUT" 2>/dev/null
  assert_contains "US-KS-2" "$(<"$OUT")"
  assert_not_contains "EU-RO-1" "$(<"$OUT")"
}

function test_should_filter_dc_to_compliance_when_compliance_flag() {
  rp::args_parse --compliance SOC_2_TYPE_2
  _stock_dc >"$OUT" 2>/dev/null
  assert_contains "US-KS-2" "$(<"$OUT")"
  assert_not_contains "EU-RO-1" "$(<"$OUT")"
}

function test_should_and_filters_when_s3_and_global_flags() {
  _s3_dcs() { printf '%s\n' "US-KS-2"; }
  rp::args_parse --s3 --global-network
  _stock_dc >"$OUT" 2>/dev/null
  assert_contains "US-KS-2" "$(<"$OUT")"
  assert_not_contains "EU-RO-1" "$(<"$OUT")"
}

function test_should_filter_dc_json_same_set_as_table_when_s3_flag() {
  _s3_dcs() { printf '%s\n' "US-KS-2"; }
  rp::args_parse --s3 --json
  _stock_dc >"$OUT"
  # --json emits the raw v2 records for the surviving DC only (no S3_API field).
  assert_equals "$(printf '%s' "$STOCK_DC_BODY" | jq -c '.dataCenters | map(select(.id=="US-KS-2"))')" "$(<"$OUT")"
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
    case "$2" in
    *cpus*) printf '{"cpus":[]}' ;;
    *) printf '{"gpus":[]}' ;;
    esac
  }
  rp::cmd_stock gpu >/dev/null 2>&1
  assert_contains "GET /catalog/gpus" "$(<"$cap")"
  rp::cmd_stock cpus >/dev/null 2>&1
  assert_contains "GET /catalog/cpus" "$(<"$cap")"
  rp::cmd_stock dc >/dev/null 2>&1
  assert_contains "GET /catalog/datacenters" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_exit_two_when_stock_verb_unknown() {
  (rp::cmd_stock __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}
