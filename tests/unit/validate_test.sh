#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/validate.sh"
  eval "$_opts"
}

# Each test starts with an empty cache and a no-op live fetch (forces the static
# fallback) so assertions are deterministic and make no network calls.
function set_up() {
  _RP_S3_DCS=()
  _s3_dcs_live() { :; }
}

function test_should_pass_when_dc_is_s3_capable() {
  rp::is_s3_dc EU-RO-1
  assert_successful_code "$?"
}

function test_should_pass_when_dc_is_s3_capable_case_insensitive() {
  rp::is_s3_dc eu-ro-1
  assert_successful_code "$?"
}

function test_should_fail_when_dc_not_s3_capable() {
  rp::is_s3_dc US-TX-1
  assert_general_error "$?"
}

function test_should_warn_when_dc_not_s3_capable() {
  local err
  err="$(rp::warn_unless_s3_dc US-TX-1 2>&1 >/dev/null)"
  assert_contains "not S3-API supported" "$err"
}

function test_should_stay_silent_when_dc_is_s3_capable() {
  local err
  err="$(rp::warn_unless_s3_dc EU-RO-1 2>&1 >/dev/null)"
  assert_empty "$err"
}

function test_should_use_live_query_when_available() {
  _s3_dcs_live() { printf 'ZZ-LIVE-1\n'; }
  rp::is_s3_dc ZZ-LIVE-1
  assert_successful_code "$?"
  # EU-RO-1 is in the fallback but not the live set; live wins, so it is not S3.
  rp::is_s3_dc EU-RO-1
  assert_general_error "$?"
}

function test_should_fall_back_when_live_query_fails() {
  _s3_dcs_live() { return 1; }
  rp::is_s3_dc EU-RO-1
  assert_successful_code "$?"
  rp::is_s3_dc US-TX-1
  assert_general_error "$?"
}

# main-shell call (bashunit skips lines run inside $(...)) so rp::warn_unless_s3_dc
# registers coverage.
function test_should_stay_silent_when_s3_capable_main_shell() {
  rp::warn_unless_s3_dc EU-RO-1 >/dev/null 2>&1
  assert_successful_code "$?"
}
