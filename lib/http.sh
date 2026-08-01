#!/usr/bin/env bash
# RunPod HTTP clients — the control-plane (REST) and serverless data-plane
# wrappers. Thin facades over rp::api_call in lib/transport.sh; all curl lives in
# the shared transport module. Sourced by bin/rp; not executed directly.
# shellcheck source=transport.sh
[[ -n "${_RP_HTTP:-}" ]] && return 0
_RP_HTTP=1

# Emit the captured response: die on a curl transport failure or HTTP >= 400
# (with the API's error message when present), otherwise print the body. $1 is the
# temp file holding the response body; $2/$3 the method/path for messages.
_rp_http_emit() {
  local tmp="$1" method="$2" path="$3"
  local status="$_RP_CURL_STATUS"
  if ((status == 0)); then
    rm -f -- "$tmp"
    rp::die "curl transport error: $method $path"
  fi
  if ((status >= 400)); then
    local msg
    msg="$(jq -rc '.error // .message // .title // empty' "$tmp" 2>/dev/null || true)"
    rm -f -- "$tmp"
    rp::die "RunPod $method $path -> HTTP $status${msg:+: $msg}"
  fi
  cat "$tmp"
  rm -f -- "$tmp"
}

# Control-plane REST call under RP_REST_BASE.
# Arguments:
#   $1 - method: HTTP method (GET/POST/DELETE/...)
#   $2 - path: REST path (e.g. /pods, "/pods/$id")
#   $3 - body: optional JSON request body
#   $4 - max_time: optional --max-time seconds (default 120)
# Returns:
#   0 - success; prints the response to stdout
#   1 - transport/HTTP error (dies)
rp::http() {
  rp::require_api_key
  rp::require_cmd curl
  local tmp
  _mktemp tmp
  rp::api_call rest "$1" "$2" "${3:-}" "${4:-120}" >"$tmp" || true
  _rp_http_emit "$tmp" "$1" "$2"
}

# Build a URL-encoded query string from alternating key/value pairs. Values are
# encoded with jq's @uri so RFC 3339 ':' and a '+00:00' offset survive intact;
# empty values are skipped. Prints nothing (not "?") when no pair survives, so
# the caller can splice the result straight onto a path.
rp::query_params() {
  local q='' k v enc
  while (($# >= 2)); do
    k="$1"
    v="$2"
    shift 2
    [[ -n "$v" ]] || continue
    enc="$(printf '%s' "$v" | jq -Rr @uri)"
    q+="${q:+&}${k}=${enc}"
  done
  [[ -n "$q" ]] && printf '?%s' "$q"
}

# Data-plane call under RP_API_BASE (https://api.runpod.ai/v2 — job submission to
# deployed serverless endpoints). runsync blocks until the job completes, so the
# default --max-time is 300 s; $4 overrides it.
# Arguments:
#   $1 - method: HTTP method
#   $2 - path: data-plane path (e.g. "/$id/runsync")
#   $3 - body: optional JSON request body
#   $4 - max_time: optional --max-time seconds (default 300)
# Returns:
#   0 - success; prints the response to stdout
#   1 - transport/HTTP error (dies)
rp::http_api() {
  rp::require_api_key
  rp::require_cmd curl
  local tmp
  _mktemp tmp
  rp::api_call api "$1" "$2" "${3:-}" "${4:-300}" >"$tmp" || true
  _rp_http_emit "$tmp" "$1" "$2"
}
