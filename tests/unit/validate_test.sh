#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Drop guards so the real modules (re)define; the S3 live check routes through
  # lib/graphql.sh's rp::graphql_soft over lib/transport.sh's curl seam, the HP
  # check through lib/http.sh's rp::http_soft on the same seam (auth.sh supplies
  # rp::auth_header, which _curl_json needs once an API key is set).
  unset _RP_TRANSPORT _RP_GRAPHQL _RP_HTTP _RP_AUTH _RP_VALIDATE
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/validate.sh"
  eval "$_opts"
}

# Each test starts with an empty cache and an unreachable live endpoint (the
# default curl double returns status 000) so assertions are deterministic and
# make no real network calls; specific tests point the double at a live body.
function set_up() {
  _RP_S3_DCS=()
  RUNPOD_API_KEY="sk-test"
  RP_GRAPHQL_URL="https://api.runpod.io/graphql"
  GQL_STATUS=000
  GQL_BODY=""
  curl() {
    local out=""
    while (($#)); do
      case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      *) shift ;;
      esac
    done
    [[ -n "$out" ]] && printf '%s' "${GQL_BODY:-}" >"$out"
    printf '%s' "${GQL_STATUS:-000}"
  }
}

function tear_down() {
  unset -f curl
  unset RUNPOD_API_KEY RP_GRAPHQL_URL GQL_STATUS GQL_BODY
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

# GraphQL is the live source for the S3 signal, so a live body is honoured over
# the static fallback: EU-RO-1 is in the fallback but not the live set, so it is
# no longer S3-capable.
function test_should_use_live_query_when_available() {
  GQL_STATUS=200
  GQL_BODY='{"data":{"dataCenters":[{"id":"ZZ-LIVE-1","s3apiEnabled":true}]}}'
  rp::is_s3_dc ZZ-LIVE-1
  assert_successful_code "$?"
  rp::is_s3_dc EU-RO-1
  assert_general_error "$?"
}

function test_should_fall_back_when_live_query_fails() {
  GQL_STATUS=500
  rp::is_s3_dc EU-RO-1
  assert_successful_code "$?"
  rp::is_s3_dc US-TX-1
  assert_general_error "$?"
}

# main-shell call (bashunit skips lines run inside $(...)) so
# rp::warn_unless_s3_dc registers coverage.
function test_should_stay_silent_when_s3_capable_main_shell() {
  rp::warn_unless_s3_dc EU-RO-1 >/dev/null 2>&1
  assert_successful_code "$?"
}

# --- high-performance tier guard (v2 catalog: GET /catalog/datacenters/{id}) ---
# The curl double's response knobs (GQL_STATUS/GQL_BODY) serve both planes: the
# S3 tests drive them through rp::graphql_soft, the HP tests through the
# rp::http_soft REST seam.

function test_should_pass_when_dc_lists_high_performance_tier() {
  GQL_STATUS=200
  GQL_BODY='{"id":"US-KS-2","networkVolumeTypes":["STANDARD","HIGH_PERFORMANCE"]}'
  rp::is_hp_dc US-KS-2
  assert_successful_code "$?"
}

function test_should_pass_when_dc_lists_high_performance_tier_case_insensitive() {
  GQL_STATUS=200
  GQL_BODY='{"id":"US-KS-2","networkVolumeTypes":["STANDARD","HIGH_PERFORMANCE"]}'
  rp::is_hp_dc us-ks-2
  assert_successful_code "$?"
}

function test_should_fail_when_dc_lacks_high_performance_tier() {
  GQL_STATUS=200
  GQL_BODY='{"id":"EU-RO-1","networkVolumeTypes":["STANDARD"]}'
  rp::is_hp_dc EU-RO-1
  assert_general_error "$?"
}

function test_should_fail_when_tiers_field_is_absent() {
  GQL_STATUS=200
  GQL_BODY='{"id":"EU-RO-1"}'
  rp::is_hp_dc EU-RO-1
  assert_general_error "$?"
}

function test_should_fail_when_catalog_unreachable() {
  GQL_STATUS=000
  rp::is_hp_dc US-KS-2
  assert_general_error "$?"
}

function test_should_fail_when_catalog_returns_404() {
  GQL_STATUS=404
  GQL_BODY='{"error":"not found"}'
  rp::is_hp_dc US-XX-9
  assert_general_error "$?"
}

function test_should_warn_when_dc_lacks_high_performance_tier() {
  GQL_STATUS=200
  GQL_BODY='{"id":"EU-RO-1","networkVolumeTypes":["STANDARD"]}'
  local err
  err="$(rp::warn_unless_hp_dc EU-RO-1 2>&1 >/dev/null)"
  assert_contains "does not list the HIGH_PERFORMANCE volume tier" "$err"
}

function test_should_stay_silent_when_dc_lists_high_performance_tier() {
  GQL_STATUS=200
  GQL_BODY='{"id":"US-KS-2","networkVolumeTypes":["STANDARD","HIGH_PERFORMANCE"]}'
  local err
  err="$(rp::warn_unless_hp_dc US-KS-2 2>&1 >/dev/null)"
  assert_empty "$err"
}

# Unknown capability (catalog unreachable) stays silent: no offline fallback
# list exists for the HP tier, so the guard must not guess.
function test_should_stay_silent_when_catalog_unreachable() {
  GQL_STATUS=000
  local err
  err="$(rp::warn_unless_hp_dc US-KS-2 2>&1 >/dev/null)"
  assert_empty "$err"
}

# main-shell call (bashunit skips lines run inside $(...)) so
# rp::warn_unless_hp_dc registers coverage.
function test_should_warn_when_dc_lacks_hp_tier_main_shell() {
  GQL_STATUS=200
  GQL_BODY='{"id":"EU-RO-1","networkVolumeTypes":["STANDARD"]}'
  rp::warn_unless_hp_dc EU-RO-1 >/dev/null 2>&1
  assert_successful_code "$?"
}
