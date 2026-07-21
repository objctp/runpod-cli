#!/usr/bin/env bash
# RunPod GraphQL client — wraps every GraphQL query/mutation against
# RP_GRAPHQL_URL. Sourced by bin/rp; not executed directly.
[[ -n "${_RP_GRAPHQL:-}" ]] && return 0
_RP_GRAPHQL=1

# Run a GraphQL query/mutation; print the `.data` object on success.
# Arguments:
#   $1 - query string
#   $2 - optional variables as a JSON object string
# Returns:
#   0 on success (`.data` to stdout); exits 1 via rp::die on transport error,
#   HTTP >= 400, or any GraphQL `errors` entry.
rp::graphql() {
  local query="$1" variables="${2:-}"
  rp::require_api_key
  rp::require_cmd curl
  local payload
  if [[ -n "$variables" ]]; then
    payload="$(jq -c -n --arg q "$query" --argjson v "$variables" '{query:$q, variables:$v}')"
  else
    payload="$(jq -c -n --arg q "$query" '{query:$q}')"
  fi
  # Auth header + payload via temp files: argv is visible in `ps` (see rp::http).
  local hdr body_in tmp status body errs
  _mktemp hdr
  _mktemp body_in
  _mktemp tmp
  printf 'Authorization: Bearer %s\n' "$RUNPOD_API_KEY" >"$hdr"
  printf '%s' "$payload" >"$body_in"
  # Content-Type must be application/json (not curl's form-urlencoded default) or
  # Apollo rejects the POST as a potential CSRF request.
  status="$(curl -sSL --connect-timeout 15 --max-time 120 -X POST \
    -H @"$hdr" -H 'Content-Type: application/json' --data @"$body_in" \
    -o "$tmp" -w '%{http_code}' "$RP_GRAPHQL_URL")" || {
    rm -f -- "$hdr" "$body_in" "$tmp"
    rp::die "curl transport error: GraphQL"
  }
  body="$(<"$tmp")"
  rm -f -- "$hdr" "$body_in" "$tmp"
  ((status >= 400)) && rp::die "GraphQL HTTP $status: $body"
  errs="$(printf '%s' "$body" | jq -c '.errors // empty' 2>/dev/null || true)"
  [[ -n "$errs" ]] && rp::die "GraphQL errors: $errs"
  printf '%s' "$body" | jq -c '.data'
}
