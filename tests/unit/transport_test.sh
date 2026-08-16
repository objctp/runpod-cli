#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _RP_TRANSPORT _RP_GRAPHQL _RP_HTTP
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/graphql.sh"
  eval "$_opts"
}

function set_up() {
  RUNPOD_API_KEY="sk-test"
  RP_REST_BASE="https://rest.test/v2"
  RP_API_BASE="https://api.test/v2"
  RP_GRAPHQL_URL="https://gql.test/graphql"
  GQL_STATUS=200
  GQL_BODY='{"data":{"ok":true}}'
  GQL_ARGS_CAPTURE="$(mktemp)"
  curl() {
    printf '%s\n' "$*" >>"$GQL_ARGS_CAPTURE"
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
  }
}

function tear_down() {
  rm -f "$GQL_ARGS_CAPTURE"
  unset -f curl
}

function test_should_resolve_rest_plane_to_rest_base() {
  rp::http GET /pods >/dev/null 2>&1
  assert_contains "https://rest.test/v2/pods" "$(<"$GQL_ARGS_CAPTURE")"
}

function test_should_resolve_api_plane_to_api_base_with_300s_timeout() {
  rp::http_api POST "/x/runsync" >/dev/null 2>&1
  local captured
  captured="$(<"$GQL_ARGS_CAPTURE")"
  assert_contains "https://api.test/v2/x/runsync" "$captured"
  assert_contains "--max-time 300" "$captured"
}

function test_should_resolve_graphql_plane_to_graphql_url() {
  rp::graphql 'query { x }' >/dev/null 2>&1
  local captured
  captured="$(<"$GQL_ARGS_CAPTURE")"
  assert_contains "https://gql.test/graphql" "$captured"
  assert_contains "-X POST" "$captured"
}

function test_should_die_on_unknown_plane() {
  (rp::api_call bogus GET /x >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_die_on_http_400_hard() {
  GQL_STATUS=400
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_return_1_on_http_400_soft() {
  GQL_STATUS=400
  rp::graphql_soft 'query { x }' >/dev/null 2>&1
  assert_general_error "$?"
}

function test_should_classify_clean_stream_as_ok() {
  assert_equals "ok" "$(_rp_stream_classify 0 "HTTP/2 200")"
}

function test_should_classify_sigint_as_interrupted_without_status() {
  assert_equals "interrupted" "$(_rp_stream_classify 130 "")"
}

function test_should_classify_sigint_as_interrupted_with_status() {
  assert_equals "interrupted" "$(_rp_stream_classify 130 "HTTP/2 200")"
}

function test_should_classify_http1_server_error_as_http_code() {
  assert_equals "http 404" "$(_rp_stream_classify 22 "HTTP/1.1 404 Not Found")"
}

function test_should_classify_http2_server_error_as_http_code() {
  assert_equals "http 429" "$(_rp_stream_classify 22 "HTTP/2 429")"
}

function test_should_classify_ended_2xx_as_ended() {
  assert_equals "ended" "$(_rp_stream_classify 18 "HTTP/2 200")"
}

function test_should_classify_curl_failure_without_status_as_transport() {
  assert_equals "transport" "$(_rp_stream_classify 7 "")"
}

function test_should_set_status_130_on_sigint() {
  curl() { return 130; }
  _curl_json "https://rest.test/v2/pods" GET >/dev/null 2>&1
  assert_equals 130 "$_RP_CURL_STATUS"
}

function test_should_exit_130_on_sigint_over_http() {
  curl() { return 130; }
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 130
}

function test_should_exit_130_on_sigint_over_graphql() {
  curl() { return 130; }
  (rp::graphql 'query { x }' >/dev/null 2>&1)
  assert_exit_code 130
}

# Q-L1: a GET (no request body) must not pass an empty string to `rm -f`, which
# the old `"${body_tmp:-}"` form did when body_tmp was unset.
_RP_RM_LOG=""
function _rp_rm_record() {
  local a
  for a in "$@"; do
    printf 'ARG[%s]\n' "$a" >>"$_RP_RM_LOG"
  done
}

function test_should_not_pass_empty_arg_to_rm_on_get() {
  _RP_RM_LOG="$(mktemp)"
  rm() { _rp_rm_record "$@"; }
  curl() {
    printf '%s' "${GQL_BODY:-}" >"${3:-/dev/null}"
    printf '%s' "${GQL_STATUS:-200}"
  }
  _curl_json "https://rest.test/v2/pods" GET >/dev/null 2>&1
  local empty=0
  while IFS= read -r line; do
    [[ "$line" == "ARG[]" ]] && empty=1
  done <"$_RP_RM_LOG"
  rm -f "$_RP_RM_LOG"
  assert_equals 0 "$empty"
}
