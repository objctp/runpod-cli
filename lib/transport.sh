#!/usr/bin/env bash
# RunPod transport — the single curl implementation shared by every client
# (control-plane REST, serverless data plane, GraphQL). All auth-header, payload,
# timeout, and status handling lives here; the public clients in lib/http.sh and
# lib/graphql.sh are thin facades over rp::api_call. Sourced by bin/rp.
[[ -n "${_RP_TRANSPORT:-}" ]] && return 0
_RP_TRANSPORT=1

# Last HTTP status from _curl_json, read by the public wrappers to apply their
# die/soft policy. Module-global: set inside _curl_json, read by callers.
declare -g _RP_CURL_STATUS=200

# Base URL for a transport plane. Resolved at call time so env overrides of
# RP_REST_BASE / RP_API_BASE / RP_GRAPHQL_URL (set in lib/common.sh) take effect.
_rp_plane_base() {
  case "$1" in
  rest) printf '%s' "${RP_REST_BASE:-https://api.runpod.io/v2}" ;;
  api) printf '%s' "${RP_API_BASE:-https://api.runpod.ai/v2}" ;;
  graphql) printf '%s' "${RP_GRAPHQL_URL:-https://api.runpod.io/graphql}" ;;
  *) return 1 ;;
  esac
}

# Default --max-time (seconds) per plane. The data plane blocks on job
# completion, so it gets a longer budget than the control plane / GraphQL.
_rp_plane_timeout() {
  case "$1" in
  rest | graphql) printf '%s' 120 ;;
  api) printf '%s' 300 ;;
  *) printf '%s' 120 ;;
  esac
}

# The one curl implementation. Never dies: prints the response body to stdout,
# records the HTTP status in _RP_CURL_STATUS, and returns non-zero only on a curl
# transport failure (status left at 000). Auth header and request body travel
# through temp files, not argv — argv is visible in `ps` for curl's lifetime, so
# -H/--data would leak the API key (and, on `rp registry create`, a registry
# password; on `rp serverless run`, the job payload).
_curl_json() {
  local url="$1" method="$2" body="${3:-}" max_time="${4:-120}"
  local hdr body_tmp tmp status out
  _mktemp hdr
  printf 'Authorization: Bearer %s\n' "$RUNPOD_API_KEY" >"$hdr"
  local -a args=(-sSL --connect-timeout 15 --max-time "$max_time" -X "$method" -H @"$hdr" -H 'Content-Type: application/json')
  _mktemp tmp
  if [[ -n "$body" ]]; then
    _mktemp body_tmp
    printf '%s' "$body" >"$body_tmp"
    args+=(--data @"$body_tmp")
  fi
  args+=("$url")
  status="$(curl "${args[@]}" -o "$tmp" -w '%{http_code}')" || {
    rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
    _RP_CURL_STATUS=000
    return 1
  }
  out="$(<"$tmp")"
  rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
  _RP_CURL_STATUS="$status"
  printf '%s' "$out"
  return 0
}

# Plane-addressed call: resolves <plane> to its base URL + default timeout, then
# delegates to _curl_json. Dies only on an unknown plane (a programming error);
# transport/HTTP outcomes are left to the caller's die/soft policy.
rp::api_call() {
  local plane="$1" method="$2" path="$3" body="${4:-}" max="${5:-}"
  local base timeout
  base="$(_rp_plane_base "$plane")" || rp::die "unknown transport plane: '$plane'"
  timeout="$(_rp_plane_timeout "$plane")"
  max="${max:-$timeout}"
  _curl_json "$base$path" "$method" "$body" "$max"
}
