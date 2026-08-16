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
# Every client (REST, data plane, GraphQL) routes through here, so the
# insecure-transport guard below covers all of them.
_rp_plane_base() {
  local base
  case "$1" in
  rest) base="${RP_REST_BASE:-https://api.runpod.io/v2}" ;;
  api) base="${RP_API_BASE:-https://api.runpod.ai/v2}" ;;
  graphql) base="${RP_GRAPHQL_URL:-https://api.runpod.io/graphql}" ;;
  *) return 1 ;;
  esac
  # Refuse plaintext transport: the Bearer token and (for registry create) the
  # password would cross the wire in cleartext. RP_ALLOW_INSECURE_HTTP=1 opts out
  # for local/test setups only.
  case "$base" in
  https://*) ;;
  *)
    [[ -n "${RP_ALLOW_INSECURE_HTTP:-}" ]] ||
      rp::die "refusing insecure HTTP transport for the '$1' plane ($base); set RP_ALLOW_INSECURE_HTTP=1 to override"
    ;;
  esac
  printf '%s' "$base"
}

# Default --max-time (seconds) per plane. The data plane blocks on job
# completion, so it gets a longer budget than the control plane / GraphQL.
_rp_plane_timeout() {
  case "$1" in
  rest) printf '%s' "$RP_TIMEOUT_REST" ;;
  graphql) printf '%s' "$RP_TIMEOUT_GRAPHQL" ;;
  api) printf '%s' "$RP_TIMEOUT_API" ;;
  *) printf '%s' "$RP_TIMEOUT_REST" ;;
  esac
}

# The one curl implementation. Never dies: prints the response body to stdout,
# records the HTTP status in _RP_CURL_STATUS, and returns non-zero only on a curl
# transport failure (status left at 000). Auth header and request body travel
# through temp files, not argv — argv is visible in `ps` for curl's lifetime, so
# -H/--data would leak the API key (and, on `rp registry create`, a registry
# password; on `rp serverless run`, the job payload).
_curl_json() {
  local url="$1" method="$2" body="${3:-}" max_time="${4:-$RP_TIMEOUT_REST}"
  local hdr body_tmp tmp status out
  _mktemp hdr
  rp::auth_header >"$hdr"
  local -a args=(-sSL --connect-timeout "$RP_TIMEOUT_CONNECT" --max-time "$max_time" -X "$method" -H @"$hdr" -H 'Content-Type: application/json')
  _mktemp tmp
  if [[ -n "$body" ]]; then
    _mktemp body_tmp
    printf '%s' "$body" >"$body_tmp"
    args+=(--data @"$body_tmp")
  fi
  args+=("$url")
  status="$(curl "${args[@]}" -o "$tmp" -w '%{http_code}')" || {
    rc=$?
    rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
    # curl exit 130 == killed by SIGINT: surface as "interrupted" (exit 130),
    # never a bogus transport error. The emit helpers (_rp_http_emit /
    # _rp_graphql_emit) check _RP_CURL_STATUS and bail quietly; the stream path
    # (_rp_stream_classify) already classifies 130 as "interrupted".
    if ((rc == 130)); then
      _RP_CURL_STATUS=130
    else
      _RP_CURL_STATUS=000
    fi
    return "$rc"
  }
  out="$(<"$tmp")"
  rm -f -- "$hdr" "$tmp" "${body_tmp:-}"
  _RP_CURL_STATUS="$status"
  printf '%s' "$out"
  return 0
}

# Classify the outcome of a streamed GET so rp::api_stream can apply its
# die/return policy. Pure (never exits) so it is unit-testable. $1 curl exit
# code, $2 the first dumped HTTP status line (empty if curl died before any
# headers arrived). Prints one of:
#   ok           — 2xx stream, curl clean
#   interrupted  — SIGINT (curl 130); quiet regardless of header state
#   http <code>  — server error >= 400 (die)
#   ended        — 2xx/3xx stream ended mid-flight (return the curl code)
#   transport    — curl failed with no usable status (die)
_rp_stream_classify() {
  local rc="$1" first="$2" status
  status="${first#HTTP/}" # -> "<version> <code> <reason…>"
  status="${status#* }"   # -> "<code> <reason…>"
  status="${status%% *}"  # -> "<code>"
  if ((rc == 0)); then
    printf 'ok'
  elif ((rc == 130)); then
    printf 'interrupted' # SIGINT: quiet even before headers
  elif [[ "$status" == [0-9][0-9][0-9] && "$status" -ge 400 ]]; then
    printf 'http %s' "$status"
  elif [[ "$status" == [0-9][0-9][0-9] ]]; then
    printf 'ended'
  else
    printf 'transport'
  fi
}

# Stream a GET endpoint (SSE logs) straight to stdout, unbuffered. The buffered
# _curl_json above would collect the whole stream into a temp file first; this
# path is for the two log surfaces that must stream. Auth + the optional
# Last-Event-ID cursor go through a header file (argv leaks the key / mangles the
# timestamp's ':'). $1 plane, $2 path (with query), $3 optional Last-Event-ID.
# HTTP >= 400 -> rp::die (status read from a -D header dump); a finished or
# interrupted live stream returns its curl code without dying.
rp::api_stream() {
  local plane="$1" path="$2" leid="${3:-}"
  local base hdr hdrs rc first verdict
  base="$(_rp_plane_base "$plane")" || rp::die "unknown transport plane: '$plane'"
  _mktemp hdr
  _mktemp hdrs
  rp::auth_header >"$hdr"
  [[ -z "$leid" ]] || printf 'Last-Event-ID: %s\n' "$leid" >>"$hdr"
  curl -s --no-buffer --connect-timeout "$RP_TIMEOUT_CONNECT" \
    -H @"$hdr" -H 'Accept: text/event-stream' -D "$hdrs" -f "$base$path"
  rc=$?
  rm -f -- "$hdr"
  # Recover the HTTP status from the dumped first line, then let the classifier
  # tell API errors (die) from a finished/interrupted/SIGINT'd stream (return).
  first="$(grep -m1 -E '^HTTP/' "$hdrs" 2>/dev/null || true)"
  rm -f -- "$hdrs"
  verdict="$(_rp_stream_classify "$rc" "$first")"
  case "$verdict" in
  ok | interrupted | ended) return "$rc" ;; # rc is 0 for ok; pass curl's code otherwise
  http\ *) rp::die "RunPod GET $path -> HTTP ${verdict#http }" ;;
  transport) rp::die "curl transport error: GET $path" ;;
  esac
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
