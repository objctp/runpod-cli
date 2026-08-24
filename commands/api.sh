#!/usr/bin/env bash
#
# Raw REST and data-plane call over rp's own transport.
#
# This is the same transport every resource verb uses, exposed for scripting
# and ad-hoc calls: it resolves the method, path, plane, body, and optional jq
# filter, then delegates to rp::http or rp::http_api — all curl, auth, timeout
# and error policy live in lib/transport.sh behind that seam. It prints the
# response body, and dies on HTTP 400 or above with the API's own message.
#
# Usage: rp api <METHOD> <path> [--body <json>] [--plane rest|api]
#               [--jq <filter>] [--limit N] [--cursor <c>]
#
# Arguments:
#   <METHOD>          HTTP method: GET/POST/PUT/DELETE/... (case-insensitive)
#   <path>            REST path under the plane base (a leading / is optional)
#
# Options:
#   --body <json>     request body; prefix with @ to read a file
#   --plane rest|api  rest = control plane (default) | api = serverless data plane
#   --jq <filter>     jq filter applied to the response (implies JSON output)
#   --limit N         cap the number of (top-level-array) items returned
#   --cursor <c>      opaque offset for the next page (pairs with --limit)
#
# Examples:
# # List pods
# $ rp api GET /pods
# # List just the pod ids
# $ rp api GET /pods --jq '.pods[] | .id'
# # Create a pod from a JSON body
# $ rp api POST /pods --body '{"name":"x","image":"y"}'
# # Run a sync job from a JSON file on the data plane
# $ rp api POST /$id/runsync --plane api --body '@job.json'
#
# API: raw call over rp::api_call — no single endpoint; the method and path
#      decide the route (control plane /v2 or data plane /v2).
#

_api_help() {
  cat <<'EOF'
Usage: rp api <METHOD> <path> [flags]

Raw call to the Runpod API — the same transport rp's resource verbs use, exposed
for scripting and ad-hoc calls. Prints the response body; dies on HTTP >= 400
with the API's error message.

  <METHOD>   HTTP method (GET/POST/PUT/DELETE/...); case-insensitive
  <path>     REST path under the plane base (a leading / is optional)
  --body     request body (JSON string); prefix with @ to read a file
  --plane    rest (control plane, default) | api (serverless data plane)
  --jq       jq filter applied to the response (implies JSON output)
              note: jq's `env` exposes the shell environment, including your
              RUNPOD_API_KEY — never run `rp api … --jq 'env'` on a shared
              terminal or in logs you don't control.
  --limit    cap the number of (top-level-array) items returned
  --cursor   opaque offset for the next page (pairs with --limit)

Examples:
  rp api GET /pods
  rp api GET /pods --jq '.pods[] | .id'
  rp api POST /pods --body '{"name":"x","image":"y"}'
  rp api POST /$id/runsync --plane api --body '@job.json'
EOF
}

###
### :::: documentation (rp doc api) :::: ######################################
###

rp::cmd_api() {
  local method="${1:-}"
  if [[ "$method" == "-h" || "$method" == "--help" || "$method" == "help" ]]; then
    _api_help
    return 0
  fi
  shift || true
  rp::args_parse "$@"
  rp::args_has help && {
    _api_help
    return 0
  }
  [[ -n "$method" ]] || rp::usage "usage: rp api <METHOD> <path> [--body <json>] [--plane rest|api] [--jq <filter>]"
  method="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
  local path
  rp::require_pos path "usage: rp api $method <path>"
  [[ "$path" == /* ]] || path="/$path"
  local plane body jqf
  plane="$(rp::args_get plane rest)"
  body="$(rp::args_get body)"
  jqf="$(rp::args_get jq)"
  if [[ -n "$body" && "$body" == @* ]]; then
    body="$(<"${body#@}")" || rp::die "cannot read --body file: ${body#@}"
  fi
  local out
  case "$plane" in
  rest) out="$(rp::http "$method" "$path" "$body")" ;;
  api) out="$(rp::http_api "$method" "$path" "$body")" ;;
  *) rp::usage "unknown --plane '$plane' (rest|api)" ;;
  esac
  rp::paginate out
  if [[ -n "$jqf" ]]; then
    printf '%s' "$out" | jq -r "$jqf"
  else
    printf '%s' "$out"
  fi
}
