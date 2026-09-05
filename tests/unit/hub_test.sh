#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/hub.sh"
  eval "$_opts"
}

function set_up() {
  # GPU-pool lookups are cached for the process lifetime; reset between tests.
  _RP_GPU_POOLS=''
  # Two pools with one shared-shape member each — mirrors the live catalogue
  # (_gpu_pools_json regroups the flat rows by .pool).
  rp::http() {
    case "$1 $2" in
    'GET /catalog/gpus'*)
      printf '{"gpus":[{"id":"NVIDIA L4","pool":"AMPERE_24"},{"id":"NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb","pool":"AMPERE_24"},{"id":"NVIDIA L40","pool":"ADA_48_PRO"}]}'
      ;;
    esac
  }
}

function tear_down() {
  unset -f rp::http
}

function test_should_pass_when_excluded_type_is_in_selected_pool() {
  rp::gpu_excluded_validate "NVIDIA L4" "AMPERE_24"
  assert_successful_code "$?"
}

function test_should_pass_when_exclusions_span_both_selected_pools() {
  rp::gpu_excluded_validate "NVIDIA L4,NVIDIA L40" "AMPERE_24,ADA_48_PRO"
  assert_successful_code "$?"
}

function test_should_fail_when_excluded_type_belongs_to_other_pool() {
  (rp::gpu_excluded_validate "NVIDIA L40" "AMPERE_24" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_name_offending_type_when_excluded_type_belongs_to_other_pool() {
  local err
  err="$(rp::gpu_excluded_validate "NVIDIA L40" "AMPERE_24" 2>&1 >/dev/null)"
  assert_contains "NVIDIA L40" "$err"
  assert_contains "ADA_48_PRO" "$err"
}

function test_should_fail_when_excluded_type_is_unknown() {
  (rp::gpu_excluded_validate "NVIDIA Bogus" "AMPERE_24" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_name_offending_type_when_excluded_type_is_unknown() {
  local err
  err="$(rp::gpu_excluded_validate "NVIDIA Bogus" "AMPERE_24" 2>&1 >/dev/null)"
  assert_contains "NVIDIA Bogus" "$err"
}

function test_should_pass_when_excluded_csv_is_empty() {
  rp::gpu_excluded_validate "" "AMPERE_24"
  assert_successful_code "$?"
}
