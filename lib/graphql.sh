#!/usr/bin/env bash
# Runpod GraphQL client — thin wrapper over the shared transport in
# lib/transport.sh. Sourced by bin/rp; not executed directly.
# shellcheck source=transport.sh
[[ -n "${_RP_GRAPHQL:-}" ]] && return 0
_RP_GRAPHQL=1

_rp_graphql_payload() {
  local query="$1" variables="${2:-}"
  if [[ -n "$variables" ]]; then
    jq -c -n --arg q "$query" --argjson v "$variables" '{query:$q, variables:$v}'
  else
    jq -c -n --arg q "$query" '{query:$q}'
  fi
}

# Emit a GraphQL response: die on a curl transport error, HTTP >= 400, or any
# `.errors` entry; otherwise print the `.data` object. $1 is the temp file
# holding the response; $2 the label for error messages.
_rp_graphql_emit() {
  local tmp="$1" label="${2:-GraphQL}"
  local status="$_RP_CURL_STATUS"
  # SIGINT (curl 130) mid-request: exit quietly as "interrupted" (130) rather
  # than a bogus transport error; the EXIT trap (_tmp_cleanup) removes temp files.
  if ((status == 130)); then
    rm -f -- "$tmp"
    exit 130
  fi
  if ((status == 0)); then
    rm -f -- "$tmp"
    rp::die "curl transport error: $label"
  fi
  if ((status == 410)); then
    rm -f -- "$tmp"
    rp::die "Runpod GraphQL API has been retired (HTTP 410 Gone). Update 'rp', or use the v2 endpoint if one is available."
  fi
  if ((status >= 400)); then
    local body
    body="$(<"$tmp")"
    rm -f -- "$tmp"
    _rp_exit_for_status "$status" "$label HTTP $status: $body"
  fi
  local errs
  errs="$(jq -c '.errors // empty' "$tmp" 2>/dev/null || true)"
  if [[ -n "$errs" ]]; then
    rm -f -- "$tmp"
    rp::die "$label errors: $errs"
  fi
  jq -c '.data' "$tmp"
  rm -f -- "$tmp"
}

# Run a GraphQL query/mutation; print the `.data` object on success.
# Arguments:
#   $1 - query: the GraphQL query/mutation string
#   $2 - variables: optional variables as a JSON object string
# Returns:
#   0 - success; prints `.data` to stdout
#   1 - transport error, HTTP >= 400, or a GraphQL `errors` entry (dies)
rp::graphql() {
  rp::require_api_key
  rp::require_cmd curl
  local payload tmp
  payload="$(_rp_graphql_payload "$1" "${2:-}")" || rp::die "invalid GraphQL variables JSON"
  _mktemp tmp
  rp::api_call graphql POST '' "$payload" "$RP_TIMEOUT_GRAPHQL" >"$tmp" || true
  _rp_graphql_emit "$tmp" "GraphQL"
}

# Soft variant of rp::graphql: identical on success, but never dies.
# Arguments:
#   $1 - query: the GraphQL query/mutation string
#   $2 - variables: optional variables as a JSON object string
# Returns:
#   0 - success; prints `.data` to stdout
#   1 - any failure (missing key/cmd, transport error, HTTP >= 400, `.errors`); no output
# Callers such as the S3 datacentre fallback use this to degrade gracefully.
rp::graphql_soft() {
  local query="$1" variables="${2:-}"
  [[ -n "${RUNPOD_API_KEY:-}" || -n "${RUNPOD_API_KEY_FILE:-}" ]] && [[ -n "${RP_GRAPHQL_URL:-}" ]] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  local payload tmp
  payload="$(_rp_graphql_payload "$query" "$variables")" || return 1
  _mktemp tmp
  rp::api_call graphql POST '' "$payload" "$RP_TIMEOUT_GRAPHQL" >"$tmp" || return 1
  _rp_graphql_emit_soft "$tmp"
}

_rp_graphql_emit_soft() {
  local tmp="$1"
  local status="$_RP_CURL_STATUS"
  if ((status == 0)) || ((status >= 400)); then
    rm -f -- "$tmp"
    return 1
  fi
  local errs
  errs="$(jq -c '.errors // empty' "$tmp" 2>/dev/null || true)"
  if [[ -n "$errs" ]]; then
    rm -f -- "$tmp"
    return 1
  fi
  jq -c '.data' "$tmp"
  rm -f -- "$tmp"
}
