#!/usr/bin/env bash
# RunPod REST client — the single curl wrapper every command module routes
# through. Sourced by bin/rp; not executed directly.
[[ -n "${_RP_HTTP:-}" ]] && return 0
_RP_HTTP=1

# Perform a RunPod REST call; print the response body on success.
# Arguments:
#   $1 - HTTP method (GET|POST|PATCH|DELETE)
#   $2 - path under RP_REST_BASE (e.g. /pods, "/pods/$id")
#   $3 - optional JSON request body
# Returns:
#   0 on 2xx/3xx (body to stdout); exits 1 via rp::die on transport error or
#   HTTP >= 400.
rp::http() {
  local method="$1" path="$2" json="${3:-}"
  rp::require_api_key
  rp::require_cmd curl
  # Bearer token and request body travel through temp files, not argv: argv is
  # visible in `ps` for the curl call's lifetime, so -H/--data would leak the
  # API key (and, on `rp registry create`, a registry password).
  local hdr
  _mktemp hdr
  printf 'Authorization: Bearer %s\n' "$RUNPOD_API_KEY" >"$hdr"
  local -a args=(-sSL --connect-timeout 15 --max-time 120 -X "$method" -H @"$hdr" -H 'Content-Type: application/json')
  local tmp body_tmp status body msg
  _mktemp tmp
  if [[ -n "$json" ]]; then
    _mktemp body_tmp
    printf '%s' "$json" >"$body_tmp"
    args+=(--data @"$body_tmp")
  fi
  args+=("$RP_REST_BASE$path")
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
