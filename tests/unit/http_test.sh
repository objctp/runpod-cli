#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Earlier test files may have sourced lib/http.sh (setting its guard) and
  # overridden rp::http; drop the guard so the real function is (re)defined here.
  unset _RP_HTTP _RP_TRANSPORT
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  source "$RP_ROOT/lib/transport.sh"
  source "$RP_ROOT/lib/http.sh"
  eval "$_opts"
}

function set_up() {
  RUNPOD_API_KEY="sk-test"
  RP_REST_BASE="https://api.runpod.io/v2"
  RP_API_BASE="https://api.runpod.ai/v2"
  OUT="$(mktemp)"
  HTTP_STATUS=200
  HTTP_RC=0
  HTTP_BODY=""
  HTTP_DATA_CAPTURE=""
  HTTP_META_CAPTURE=""
  # curl double: write the configured body to the -o file, print the configured
  # status code (curl's -w output), return HTTP_RC for transport errors, copy
  # the --data request body to HTTP_DATA_CAPTURE when set, and record
  # "<url> <max-time>" into HTTP_META_CAPTURE when set (files, not variables:
  # rp::http runs curl in a $() subshell, so assignments would be lost).
  curl() {
    local out="" data="" url="" maxtime=""
    while (($#)); do
      case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      --data)
        data="$2"
        shift 2
        ;;
      --max-time)
        maxtime="$2"
        shift 2
        ;;
      https://*)
        url="$1"
        shift
        ;;
      *) shift ;;
      esac
    done
    [[ -n "$data" && -n "$HTTP_DATA_CAPTURE" ]] && cp "${data#@}" "$HTTP_DATA_CAPTURE"
    [[ -n "$HTTP_META_CAPTURE" ]] && printf '%s %s' "$url" "$maxtime" >"$HTTP_META_CAPTURE"
    [[ -n "$out" ]] && printf '%s' "${HTTP_BODY:-}" >"$out"
    printf '%s' "${HTTP_STATUS:-200}"
    return "${HTTP_RC:-0}"
  }
}

function tear_down() {
  rm -f "$OUT"
  unset -f curl
}

function test_should_return_body_when_get_succeeds() {
  HTTP_BODY='{"id":"p1"}'
  HTTP_STATUS=200
  rp::http GET /pods >"$OUT"
  assert_equals '{"id":"p1"}' "$(<"$OUT")"
}

function test_should_send_body_when_json_given() {
  local body_capture
  body_capture="$(mktemp)"
  HTTP_BODY='{"id":"new"}'
  HTTP_STATUS=200
  HTTP_DATA_CAPTURE="$body_capture"
  rp::http POST /pods '{"image":"x"}' >"$OUT"
  assert_equals "new" "$(jq -r '.id' "$OUT")"
  assert_equals "x" "$(jq -r '.image' "$body_capture")"
  rm -f "$body_capture"
}

function test_should_exit_one_when_http_status_is_5xx_error() {
  HTTP_BODY='{"error":"boom"}'
  HTTP_STATUS=500
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_include_status_and_message_when_http_error() {
  HTTP_BODY='{"error":"not found"}'
  HTTP_STATUS=404
  local err
  err="$(rp::http GET /pods/x 2>&1 >/dev/null)"
  assert_contains "HTTP 404" "$err"
  assert_contains "not found" "$err"
}

function test_should_exit_four_when_http_status_is_404() {
  HTTP_BODY='{"error":"not found"}'
  HTTP_STATUS=404
  (rp::http GET /pods/x >/dev/null 2>&1)
  assert_exit_code 4
}

function test_should_exit_three_when_http_401_rejected_key() {
  HTTP_BODY='{"error":"unauthorized"}'
  HTTP_STATUS=401
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_exit_three_when_http_403_rejected_key() {
  HTTP_BODY='{"error":"forbidden"}'
  HTTP_STATUS=403
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_exit_one_when_curl_transport_fails() {
  HTTP_RC=7
  HTTP_STATUS=000
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_report_transport_error_when_curl_fails() {
  HTTP_RC=7
  HTTP_STATUS=000
  local err
  err="$(rp::http GET /pods 2>&1 >/dev/null)"
  assert_contains "transport error" "$err"
}

function test_should_exit_three_when_api_key_unset() {
  unset RUNPOD_API_KEY
  (rp::http GET /pods >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_use_rest_base_and_default_timeout_when_http_called() {
  local meta
  meta="$(mktemp)"
  HTTP_BODY='{}'
  HTTP_META_CAPTURE="$meta"
  rp::http GET /pods >"$OUT"
  assert_equals "https://api.runpod.io/v2/pods 120" "$(<"$meta")"
  rm -f "$meta"
}

function test_should_use_api_base_and_default_timeout_when_http_api_called() {
  local meta
  meta="$(mktemp)"
  HTTP_BODY='{}'
  HTTP_META_CAPTURE="$meta"
  rp::http_api POST /e1/runsync '{"input":{}}' >"$OUT"
  assert_equals "https://api.runpod.ai/v2/e1/runsync 300" "$(<"$meta")"
  rm -f "$meta"
}

function test_should_pass_max_time_override_when_http_api_given_timeout() {
  local meta
  meta="$(mktemp)"
  HTTP_BODY='{}'
  HTTP_META_CAPTURE="$meta"
  rp::http_api POST /e1/run '{"input":{}}' 600 >"$OUT"
  assert_equals "https://api.runpod.ai/v2/e1/run 600" "$(<"$meta")"
  rm -f "$meta"
}

function test_should_send_body_via_data_file_when_http_api_called() {
  local body_capture
  body_capture="$(mktemp)"
  HTTP_BODY='{"id":"job1"}'
  HTTP_DATA_CAPTURE="$body_capture"
  rp::http_api POST /e1/runsync '{"input":{"image":"b64"}}' >"$OUT"
  assert_equals "job1" "$(jq -r '.id' "$OUT")"
  assert_equals "b64" "$(jq -r '.input.image' "$body_capture")"
  rm -f "$body_capture"
}

function test_query_params_should_be_empty_when_no_pairs() {
  assert_equals "" "$(rp::query_params)"
}

function test_query_params_should_emit_single_pair() {
  assert_equals "?k=v" "$(rp::query_params k v)"
}

function test_query_params_should_emit_two_pairs_joined() {
  assert_equals "?k=v&k2=v2" "$(rp::query_params k v k2 v2)"
}

function test_query_params_should_skip_empty_values() {
  assert_equals "?k=v&kept=keep" "$(rp::query_params k v empty "" kept keep)"
}

function test_query_params_should_keep_colon_readable_in_timestamp() {
  assert_equals "?startTime=2026-07-01T00:00:00Z" "$(rp::query_params startTime "2026-07-01T00:00:00Z")"
}

# ':' is readable but '+' must stay %2B, or the API decodes the offset as a space.
function test_query_params_should_encode_plus_offset() {
  assert_equals "?t=2026-07-01T00:00:00%2B00:00" "$(rp::query_params t "2026-07-01T00:00:00+00:00")"
}

function test_query_params_should_keep_csv_comma_readable() {
  assert_equals "?product=POD,SERVERLESS" "$(rp::query_params product "POD,SERVERLESS")"
}

# '&' and '=' stay encoded so a value can never inject an extra parameter.
function test_query_params_should_encode_query_separators() {
  assert_equals "?q=a%26admin%3Dtrue" "$(rp::query_params q "a&admin=true")"
}
