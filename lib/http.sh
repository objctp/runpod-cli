#!/usr/bin/env bash
# RunPod HTTP clients — the curl wrappers every command module routes through:
# rp::http for the control plane (REST), rp::http_api for the serverless data
# plane. Sourced by bin/rp; not executed directly.
[[ -n "${_RP_HTTP:-}" ]] && return 0
_RP_HTTP=1

# Shared curl core behind rp::http / rp::http_api.
# Arguments:
#   $1 - base URL (no trailing slash)
#   $2 - HTTP method (GET|POST|PATCH|DELETE)
#   $3 - path under the base (e.g. /pods, "/$id/runsync")
#   $4 - optional JSON request body
#   $5 - optional curl --max-time in seconds (default 120)
# Returns:
#   0 on 2xx/3xx (body to stdout); exits 1 via rp::die on transport error or
#   HTTP >= 400.
_http_request() {
  local base="$1" method="$2" path="$3" json="${4:-}" max_time="${5:-120}"
  rp::require_api_key
  rp::require_cmd curl
  # Bearer token and request body travel through temp files, not argv: argv is
  # visible in `ps` for the curl call's lifetime, so -H/--data would leak the
  # API key (and, on `rp registry create`, a registry password; on
  # `rp endpoint run`, the job payload).
  local hdr
  _mktemp hdr
  printf 'Authorization: Bearer %s\n' "$RUNPOD_API_KEY" >"$hdr"
  local -a args=(-sSL --connect-timeout 15 --max-time "$max_time" -X "$method" -H @"$hdr" -H 'Content-Type: application/json')
  local tmp body_tmp status body msg
  _mktemp tmp
  if [[ -n "$json" ]]; then
    _mktemp body_tmp
    printf '%s' "$json" >"$body_tmp"
    args+=(--data @"$body_tmp")
  fi
  args+=("$base$path")
  status="$(curl "${args[@]}" -o "$tmp" -w '%{http_code}')" || {
    rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
    rp::die "curl transport error: $method $path"
  }
  body="$(<"$tmp")"
  rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
  if ((status >= 400)); then
    msg="$(printf '%s' "$body" | jq -rc '.error // .message // .title // empty' 2>/dev/null || true)"
    rp::die "RunPod $method $path -> HTTP $status${msg:+: $msg}"
  fi
  printf '%s' "$body"
}

# Control-plane REST call under RP_REST_BASE.
# Arguments: $1 method, $2 path (e.g. /pods, "/pods/$id"), $3 optional JSON body.
rp::http() {
  _http_request "$RP_REST_BASE" "$1" "$2" "${3:-}"
}

# Data-plane call under RP_API_BASE (https://api.runpod.ai/v2 — job submission
# to deployed serverless endpoints). runsync blocks until the job completes, so
# the default --max-time is 300 s; $4 overrides it.
# Arguments: $1 method, $2 path (e.g. "/$id/runsync"), $3 optional JSON body,
# $4 optional --max-time seconds.
rp::http_api() {
  _http_request "$RP_API_BASE" "$1" "$2" "${3:-}" "${4:-300}"
}
