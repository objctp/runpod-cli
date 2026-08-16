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
  # SIGINT (curl 130) mid-request: exit quietly as "interrupted" (130) rather
  # than a bogus transport error; the EXIT trap (_tmp_cleanup) removes temp files.
  if ((status == 130)); then
    rm -f -- "$tmp"
    exit 130
  fi
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
  rp::api_call rest "$1" "$2" "${3:-}" "${4:-$RP_TIMEOUT_REST}" >"$tmp" || true
  _rp_http_emit "$tmp" "$1" "$2"
}

# Build a query string from alternating key/value pairs; empty values are
# skipped. Prints nothing (not "?") when no pair survives, so the caller can
# splice the result straight onto a path.
#
# Values go through jq's @uri, which encodes everything outside the unreserved
# set, then ',' and ':' are decoded back. RFC 3986 §3.4 allows both unencoded in
# a query, and they are the only reserved characters this CLI emits — csv
# filters (--product POD,SERVERLESS) and RFC 3339 timestamps (--start). Leaving
# them readable keeps logged URLs and error messages legible. Everything else
# stays encoded: '+' in particular must remain %2B or a '+00:00' offset decodes
# as a space, and '&'/'='/';' would split the query itself.
rp::query_params() {
  local q='' k v enc
  while (($# >= 2)); do
    k="$1"
    v="$2"
    shift 2
    [[ -n "$v" ]] || continue
    enc="$(printf '%s' "$v" | jq -Rr @uri)"
    enc="${enc//%2C/,}"
    enc="${enc//%3A/:}"
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
  rp::api_call api "$1" "$2" "${3:-}" "${4:-$RP_TIMEOUT_API}" >"$tmp" || true
  _rp_http_emit "$tmp" "$1" "$2"
}

# Stream a control-plane SSE log endpoint (GET) straight to stdout under
# RP_REST_BASE. $1 path (with its query string), $2 optional Last-Event-ID cursor.
# Used by the pod/serverless logs verbs; the buffered rp::http cannot stream.
rp::stream_rest() {
  rp::require_api_key
  rp::require_cmd curl
  rp::api_stream rest "$1" "${2:-}"
}
