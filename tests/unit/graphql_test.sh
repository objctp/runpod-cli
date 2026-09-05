#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Earlier test files may have sourced lib/graphql.sh (setting its guard) and
  # overridden rp::graphql; drop the guard so the real function is (re)defined.
  unset _RP_GRAPHQL _RP_TRANSPORT
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/graphql.sh"
  eval "$_opts"
}

function set_up() {
  RUNPOD_API_KEY="sk-test"
  OUT="$(mktemp)"
  GQL_STATUS=200
  GQL_RC=0
  GQL_BODY=""
  GQL_ARGS_CAPTURE=""
  # curl double: write the configured body to the -o file, print the configured
  # status code (curl's -w output), return GQL_RC for transport errors, and
  # record the full argv to GQL_ARGS_CAPTURE when set.
  curl() {
    [[ -n "$GQL_ARGS_CAPTURE" ]] && printf '%s\n' "$*" >>"$GQL_ARGS_CAPTURE"
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
    printf '%s' "${GQL_STATUS:-200}"
    return "${GQL_RC:-0}"
  }
}

function tear_down() {
  rm -f "$OUT"
  unset -f curl
}

function test_should_send_json_content_type_header() {
  # Apollo blocks form-urlencoded POSTs as CSRF; the client must send JSON.
  local args_capture
  args_capture="$(mktemp)"
  GQL_BODY='{"data":{"myself":{"id":"u1"}}}'
  GQL_STATUS=200
  GQL_ARGS_CAPTURE="$args_capture"
  rp::graphql 'query { myself { id } }' >/dev/null
  assert_contains "Content-Type: application/json" "$(<"$args_capture")"
  rm -f "$args_capture"
}

function test_should_return_data_when_query_succeeds_without_variables() {
  GQL_BODY='{"data":{"myself":{"id":"u1"}}}'
  GQL_STATUS=200
  rp::graphql 'query { myself { id } }' >"$OUT"
  assert_equals '{"myself":{"id":"u1"}}' "$(<"$OUT")"
}

function test_should_send_variables_when_provided() {
  GQL_BODY='{"data":{"listing":{"id":"h1"}}}'
  GQL_STATUS=200
  rp::graphql 'query($id:String!){listing(id:$id){id}}' '{"id":"h1"}' >"$OUT"
  assert_equals '{"listing":{"id":"h1"}}' "$(<"$OUT")"
}

function test_should_exit_one_when_http_status_is_error() {
  GQL_BODY='{"error":"bad"}'
  GQL_STATUS=400
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_give_clear_message_on_410_graphql_retired() {
  GQL_BODY='{"error":"gone"}'
  GQL_STATUS=410
  local err rc
  err="$(rp::graphql 'query { x }' 2>&1 >/dev/null)"
  rc=$?
  assert_contains "GraphQL API has been retired" "$err"
  assert_equals 1 "$rc"
}

function test_should_exit_four_when_http_status_is_404() {
  GQL_BODY='{"error":"not found"}'
  GQL_STATUS=404
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 4
}

function test_should_exit_three_when_http_401_rejected_key() {
  GQL_BODY='{"error":"unauthorized"}'
  GQL_STATUS=401
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_exit_one_when_graphql_returns_errors() {
  GQL_BODY='{"errors":[{"message":"field not found"}]}'
  GQL_STATUS=200
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_report_graphql_errors_when_present() {
  GQL_BODY='{"errors":[{"message":"field not found"}]}'
  GQL_STATUS=200
  local err
  err="$(rp::graphql 'query { x }' 2>&1 >/dev/null)"
  assert_contains "GraphQL errors" "$err"
}

function test_should_exit_one_when_curl_transport_fails() {
  GQL_RC=7
  GQL_STATUS=000
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_exit_three_when_api_key_unset() {
  unset RUNPOD_API_KEY
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 3
}

# A 200 with a non-JSON body (proxy interstitial, HTML error page) must fail as
# a GraphQL error, not print a raw jq parse error from the extraction.
function test_should_die_clearly_when_200_body_is_not_json() {
  GQL_BODY='<html>bad gateway</html>'
  GQL_STATUS=200
  local err rc
  err="$(rp::graphql 'query { x }' 2>&1 >/dev/null)"
  rc=$?
  assert_contains "invalid JSON body" "$err"
  assert_equals "1" "$rc"
}

function test_should_return_one_quietly_when_soft_200_body_is_not_json() {
  GQL_BODY='<html>bad gateway</html>'
  GQL_STATUS=200
  local out err
  out="$(rp::graphql_soft 'query { x }' 2>"$OUT")"
  err="$(<"$OUT")"
  assert_empty "$out"
  assert_empty "$err"
}

# graphql_soft must consult the account store, not just raw env: a user logged
# in via `rp auth login` (no RUNPOD_API_KEY exported) would otherwise always
# fall back to the stale static S3-DC snapshot. _rp_env_load lives in bin/rp,
# so a faithful stub of its account load is defined — and unset — here only.
function test_should_see_the_account_store_in_graphql_soft() {
  _rp_env_load() {
    local f="$1" line
    [[ -f "$f" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == RUNPOD_API_KEY=* ]]; then
        export "RUNPOD_API_KEY=${line#RUNPOD_API_KEY=}"
      fi
    done <"$f"
    return 0
  }
  local dir f out rc
  dir="$(mktemp -d)"
  f="$dir/acme"
  printf 'RUNPOD_API_KEY=sk-stored\n' >"$f"
  chmod 600 "$f"
  unset RUNPOD_API_KEY RUNPOD_API_KEY_FILE
  GQL_BODY='{"data":{"dc":"live"}}'
  GQL_STATUS=200
  RP_ACCOUNT=acme RP_CREDS_DIR="$dir" RP_ACTIVE_FILE="$dir/active"
  out="$(rp::graphql_soft 'query { x }' 2>/dev/null)"
  rc=$?
  RP_ACCOUNT=""
  chmod 600 "$f"
  rm -rf "$dir"
  unset -f _rp_env_load RUNPOD_API_KEY
  assert_equals '{"dc":"live"}' "$out"
  assert_equals "0" "$rc"
}
