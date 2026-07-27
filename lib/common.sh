#!/usr/bin/env bash
# Shared runtime: coloured output helpers, distinct-code exiters, env/secret guards, temp-file cleanup, and the core-tool check. Sourced first by bin/rp.
[[ -n "${_RP_COMMON:-}" ]] && return 0
_RP_COMMON=1

RP_ROOT="${RP_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
RP_REST_BASE="${RP_REST_BASE:-https://rest.runpod.io/v1}"
RP_API_BASE="${RP_API_BASE:-https://api.runpod.ai/v2}"
RP_GRAPHQL_URL="${RP_GRAPHQL_URL:-https://api.runpod.io/graphql}"

# Distinct exit codes so `rp` is scriptable without parsing stderr:
#   1 general/transport/API error · 2 usage · 3 auth · 4 not-found
RP_EXIT_USAGE=2
RP_EXIT_AUTH=3
RP_EXIT_NOTFOUND=4

if [[ -t 2 ]]; then
  RP_C_RED=$'\033[31m'
  RP_C_YEL=$'\033[33m'
  RP_C_GRN=$'\033[32m'
  RP_C_RST=$'\033[0m'
else
  RP_C_RED=''
  RP_C_YEL=''
  RP_C_GRN=''
  RP_C_RST=''
fi

# --- temp files & startup checks ---

# Temp paths registered for removal on exit or interruption.
_RP_TEMPS=()

_error() { printf '%s%s%s\n' "$RP_C_RED" "$*" "$RP_C_RST" >&2; }

_auth() {
  _error "$*"
  exit "$RP_EXIT_AUTH"
}

# Remove every registered temp file (idempotent — safe to call from a trap).
_tmp_cleanup() {
  ((${#_RP_TEMPS[@]})) || return 0
  rm -f -- "${_RP_TEMPS[@]}"
  _RP_TEMPS=()
}

# Create a temp file, register it for the cleanup trap, and assign its path to
# the nameref named in $1. Callers MUST pass a variable name (`_mktemp tmp`),
# not command substitution (`x=$(_mktemp)`) — `$()` runs in a subshell, which
# would silently discard the registration (and the INT/TERM trap that depends on
# it). Because bin/rp's INT/TERM trap is inherited, each `$()` subshell cleans
# its own temps; the main-process EXIT trap cleans the rest.
_mktemp() {
  local -n mktemp_out="$1"
  mktemp_out="$(mktemp)" || return 1
  _RP_TEMPS+=("$mktemp_out")
}

# Warn (stderr) if $1 is readable by group or other — guards credential files
# like .env. Portable across macOS (stat -f) and Linux (stat -c). Must return 0
# in the private case too: callers run it bare under `set -e`, so a non-zero
# return here would abort rp whenever .env is correctly locked down (mode 600).
_warn_if_world_readable() {
  local f="$1" perm
  perm="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)" || return 0
  [[ "$perm" =~ ^[0-7]+$ ]] || return 0
  if ((8#$perm & 077)); then
    rp::warn "note: $f is group/world-readable (mode $perm); tighten with 'chmod 600 $f' — it holds your API key"
  fi
}

rp::info() { printf '%s\n' "$*" >&2; }

rp::warn() { printf '%s%s%s\n' "$RP_C_YEL" "$*" "$RP_C_RST" >&2; }

rp::ok() { printf '%s%s%s\n' "$RP_C_GRN" "$*" "$RP_C_RST" >&2; }

rp::die() {
  _error "$*"
  exit 1
}

# Specialised exiters: same stderr output as rp::die, distinct exit codes.
rp::usage() {
  _error "$*"
  exit "$RP_EXIT_USAGE"
}

rp::notfound() {
  _error "$*"
  exit "$RP_EXIT_NOTFOUND"
}

rp::require_api_key() {
  [[ -n "${RUNPOD_API_KEY:-}" ]] || _auth "RUNPOD_API_KEY unset — add it to .env (console > Settings > API Keys)"
}

rp::require_s3_creds() {
  [[ -n "${RUNPOD_S3_ACCESS_KEY:-}" ]] || _auth "RUNPOD_S3_ACCESS_KEY unset — create an S3 API key (console > Settings > S3 API Keys)"
  [[ -n "${RUNPOD_S3_SECRET_KEY:-}" ]] || _auth "RUNPOD_S3_SECRET_KEY unset — create an S3 API key (console > Settings > S3 API Keys)"
}

rp::require_cmd() {
  command -v "$1" >/dev/null 2>&1 || rp::usage "required command not found: $1"
}

# Die unless $1 is a non-negative integer (empty is allowed — means unset). $2
# is the flag name for the message. Guards numeric flags so a typo yields a clear
# error instead of an opaque jq/arithmetic failure downstream.
rp::require_uint() {
  local val="$1" name="$2"
  [[ -z "$val" || "$val" =~ ^[0-9]+$ ]] || rp::usage "--$name must be a positive integer (got '$val')"
}

# Fail fast if a core tool the CLI depends on is missing. Feature-gated tools
# (aws, huggingface-cli, ssh-keygen) are still checked at their own call sites.
rp::check_core() {
  local missing=() c
  for c in jq curl awk head sort paste; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  ((${#missing[@]})) || return 0
  rp::usage "missing required commands: ${missing[*]} (install via your package manager)"
}

# Render a JSON array (or object wrapping one) as a TSV table with a header row.
# $1 is the JSON; the remaining args are the field names to extract in order;
# missing values render as empty. Used by list/search commands in human mode.
rp::table() {
  local json="$1"
  shift
  local hdr
  hdr="$(printf '\t%s' "$@")"
  printf '%s\n' "${hdr#$'\t'}"
  printf '%s' "$json" | jq -r --argjson fields "$(printf '%s\n' "$@" | jq -R . | jq -sc .)" \
    '(if . == null then [] else . end) | .[] | [ $fields[] as $f | .[$f] // "" ] | @tsv'
}
