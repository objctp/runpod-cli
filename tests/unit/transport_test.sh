#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _RP_TRANSPORT _RP_GRAPHQL _RP_HTTP
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
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
  _RP_RATELIMIT_WARNED=0
  _RP_RATE_LIMIT=""
  _RP_RATE_LIMIT_POLICY=""
  _RP_RETRY_AFTER=""
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

# Streaming path must honour the same exit-code contract as the buffered one:
# 404 -> not-found (4) and 401/403 rejected key -> auth (3). The curl double
# writes a header dump (the -D file) and returns 22 (curl's >=400 "error").
function _stream_curl() {
  local hdrs=""
  while (($#)); do
    case "$1" in
    -D)
      hdrs="$2"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  printf 'HTTP/1.1 %s %s\r\n\r\n' "${_STREAM_STATUS:-404}" "${_STREAM_REASON:-Not Found}" >"$hdrs"
  return "${_STREAM_RC:-22}"
}

function test_should_exit_four_when_stream_404() {
  _STREAM_STATUS=404 _STREAM_REASON="Not Found" _STREAM_RC=22
  curl() { _stream_curl "$@"; }
  (rp::api_stream rest /pods/x >/dev/null 2>&1)
  assert_exit_code 4
}

function test_should_exit_three_when_stream_401_rejected_key() {
  _STREAM_STATUS=401 _STREAM_REASON="Unauthorized" _STREAM_RC=22
  curl() { _stream_curl "$@"; }
  (rp::api_stream rest /pods >/dev/null 2>&1)
  assert_exit_code 3
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
  _curl_json "https://rest.test/v2/pods" GET >/dev/null 2>&1
  local empty=0
  while IFS= read -r line; do
    [[ "$line" == "ARG[]" ]] && empty=1
  done <"$_RP_RM_LOG"
  rm -f "$_RP_RM_LOG"
  assert_equals 0 "$empty"
}

# --insecure: the buffered curl seam must pass -k so a pod whose CA bundle can't
# validate the API still works. RP_ARGS[insecure] is what rp::args_parse sets
# after `--insecure`/`-k`.
function test_should_pass_k_when_insecure_flag_set() {
  RP_ARGS[insecure]=1
  rp::http GET /pods >/dev/null 2>&1
  assert_contains "-k" "$(<"$GQL_ARGS_CAPTURE")"
  unset 'RP_ARGS[insecure]'
}

function test_should_not_pass_k_when_insecure_flag_unset() {
  unset 'RP_ARGS[insecure]'
  rp::http GET /pods >/dev/null 2>&1
  local captured
  captured="$(<"$GQL_ARGS_CAPTURE")"
  [[ "$captured" == *"-k"* ]] && fail "-k should be absent without --insecure (got: $captured)"
  assert_equals 0 0
}

# The streaming seam (SSE logs) must also honour --insecure.
function test_should_pass_k_on_stream_when_insecure_flag_set() {
  RP_ARGS[insecure]=1
  curl() {
    printf '%s\n' "$*" >>"$GQL_ARGS_CAPTURE"
    local hdrs=""
    while (($#)); do
      case "$1" in
      -D)
        hdrs="$2"
        shift 2
        ;;
      *) shift ;;
      esac
    done
    [[ -n "$hdrs" ]] && printf 'HTTP/1.1 200 OK\r\n\r\n' >"$hdrs"
    return 0
  }
  (rp::api_stream rest /pods/x >/dev/null 2>&1)
  assert_contains "-k" "$(<"$GQL_ARGS_CAPTURE")"
  unset 'RP_ARGS[insecure]'
}

# Curl double that also dumps the request headers (-H @file) into $HDR_CAP so
# the extra-headers seam can be asserted without exposing argv.
_hdr_cap_curl() {
  local out="" a
  while (($#)); do
    case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H)
      [[ "$2" == @* ]] && cat "${2#@}" >>"$HDR_CAP"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  [[ -n "$out" ]] && printf '%s' "${GQL_BODY:-}" >"$out"
  printf '%s' "${GQL_STATUS:-200}"
}

# Extra request headers travel inside the auth header temp file (-H @file),
# never argv — the same leak-safety rule as the API key and the job payload.
function test_should_send_extra_headers_via_header_file() {
  HDR_CAP="$(mktemp)"
  curl() { _hdr_cap_curl "$@"; }
  rp::http_api POST /x/runsync '{}' 5 'X-Runpod-Worker-Id: strict pod-1' >/dev/null 2>&1
  assert_contains "Authorization: Bearer sk-test" "$(<"$HDR_CAP")"
  assert_contains "X-Runpod-Worker-Id: strict pod-1" "$(<"$HDR_CAP")"
  rm -f "$HDR_CAP"
}

function test_should_not_send_extra_headers_when_unset() {
  HDR_CAP="$(mktemp)"
  curl() { _hdr_cap_curl "$@"; }
  rp::http GET /pods >/dev/null 2>&1
  assert_contains "Authorization: Bearer sk-test" "$(<"$HDR_CAP")"
  assert_not_contains "X-Runpod" "$(<"$HDR_CAP")"
  rm -f "$HDR_CAP"
}

# Curl double for the response-header capture: writes the raw header block
# (CRLF, like a real curl -D dump) from $_RESP_HEADERS into the -D file and the
# body into the -o file.
_resp_curl() {
  local out="" dump=""
  while (($#)); do
    case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -D)
      dump="$2"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  [[ -n "$dump" ]] && printf '%s' "$_RESP_HEADERS" >"$dump"
  [[ -n "$out" ]] && printf '%s' "${GQL_BODY:-}" >"$out"
  printf '%s' "${GQL_STATUS:-200}"
}

# The response's X-Runpod-Worker-Id (load-balancer endpoints) lands in
# _RP_WORKER_ID, the same pattern as _RP_SUNSET.
function test_should_capture_worker_id_from_response_header() {
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\nX-Runpod-Worker-Id: pod-9\r\n'
  curl() { _resp_curl "$@"; }
  rp::http_api POST /e/runsync '{}' >/dev/null 2>&1
  assert_equals "pod-9" "$_RP_WORKER_ID"
}

# The capture resets per request, so a headerless response never leaks the
# previous call's worker id into the caller's output.
function test_should_reset_worker_id_when_response_has_none() {
  _RP_WORKER_ID="stale-pod"
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\n'
  curl() { _resp_curl "$@"; }
  rp::http_api POST /e/runsync '{}' >/dev/null 2>&1
  assert_equals "" "$_RP_WORKER_ID"
}

# The v2 rate-limit family lands in module globals, the _RP_SUNSET pattern.
function test_should_capture_ratelimit_headers_from_response() {
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\nRateLimit: "minute";r=0;t=12, "hour";r=2800;t=1812\r\nRateLimit-Policy: "minute";q=60;w=60\r\nRetry-After: 12\r\n'
  curl() { _resp_curl "$@"; }
  rp::http GET /pods >/dev/null 2>&1
  assert_equals '"minute";r=0;t=12, "hour";r=2800;t=1812' "$_RP_RATE_LIMIT"
  assert_equals '"minute";q=60;w=60' "$_RP_RATE_LIMIT_POLICY"
  assert_equals "12" "$_RP_RETRY_AFTER"
}

function test_should_reset_ratelimit_headers_when_response_has_none() {
  _RP_RATE_LIMIT="stale" _RP_RATE_LIMIT_POLICY="stale" _RP_RETRY_AFTER="stale"
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\n'
  curl() { _resp_curl "$@"; }
  rp::http GET /pods >/dev/null 2>&1
  assert_equals "" "$_RP_RATE_LIMIT"
  assert_equals "" "$_RP_RATE_LIMIT_POLICY"
  assert_equals "" "$_RP_RETRY_AFTER"
}

# Binding window = fewest remaining; ties break to the soonest reset. The
# documented wire example, verbatim.
function test_should_parse_binding_window_from_ratelimit_value() {
  assert_equals "minute 0 12" "$(_rp_ratelimit_binding '"minute";r=0;t=12, "hour";r=2800;t=1812, "day";r=49500;t=45012')"
}

function test_should_pick_smallest_remaining_across_windows() {
  assert_equals "minute 3 45" "$(_rp_ratelimit_binding '"hour";r=2800;t=1812, "minute";r=3;t=45')"
}

function test_should_break_remaining_ties_by_soonest_reset() {
  assert_equals "minute 0 12" "$(_rp_ratelimit_binding '"day";r=0;t=45012, "minute";r=0;t=12')"
}

function test_should_return_nothing_when_ratelimit_value_unparseable() {
  assert_equals "" "$(_rp_ratelimit_binding "garbage")"
  assert_equals "" "$(_rp_ratelimit_binding "")"
}

# Zero-padded counts must not trip bash's octal arithmetic ("value too great
# for base" on 08/09 would mis-select the binding window).
function test_should_normalise_zero_padded_counts() {
  assert_equals "minute 8 9" "$(_rp_ratelimit_binding '"minute";r=08;t=09')"
}

# Parameters are scanned after the quoted item, so a window name that happens
# to contain "r=…" can never pass for a count.
function test_should_not_scan_window_name_for_params() {
  assert_equals "" "$(_rp_ratelimit_binding '"r=9999";t=5')"
}

# A zero-remaining window warns once (stderr passes through rp::http), then
# stays quiet for the rest of the process.
function test_should_warn_when_window_exhausted() {
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\nRateLimit: "minute";r=0;t=12\r\n'
  curl() { _resp_curl "$@"; }
  local err
  err="$(rp::http GET /pods 2>&1 >/dev/null)"
  assert_contains "rate limit: minute window exhausted (resets in 12s); expect HTTP 429" "$err"
}

function test_should_warn_only_once_per_process() {
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\nRateLimit: "minute";r=0;t=12\r\n'
  curl() { _resp_curl "$@"; }
  rp::http GET /pods 2>/dev/null >/dev/null
  local err
  err="$(rp::http GET /pods 2>&1 >/dev/null)"
  assert_not_contains "rate limit:" "$err"
}

function test_should_not_warn_when_remaining_is_nonzero() {
  _RESP_HEADERS=$'HTTP/1.1 200 OK\r\nRateLimit: "minute";r=59;t=12\r\n'
  curl() { _resp_curl "$@"; }
  local err
  err="$(rp::http GET /pods 2>&1 >/dev/null)"
  assert_not_contains "rate limit:" "$err"
}
