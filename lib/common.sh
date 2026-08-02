#!/usr/bin/env bash
# Shared runtime: coloured output helpers, verb output policy (rp::emit_json_or), distinct-code exiters, env/secret guards, temp-file cleanup, and the core-tool check. Sourced first by bin/rp.
[[ -n "${_RP_COMMON:-}" ]] && return 0
_RP_COMMON=1

RP_ROOT="${RP_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
# Tunable defaults / magic values (timeouts, size defaults, data tables) live in
# lib/constants.sh. Sourced here so every consumer — including the test harnesses
# that source common.sh directly — has them without a separate include.
. "$RP_ROOT/lib/constants.sh"
# Control-plane REST API v2 (https://api.runpod.io/v2). Override to pin an
# older base or a staging host. The job-submission data plane (RP_API_BASE) is
# a different host (api.runpod.ai) and is already v2 — it is unchanged.
RP_REST_BASE="${RP_REST_BASE:-https://api.runpod.io/v2}"
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

###
### :::: temp files & startup checks :::: ######################################
###

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
  # Probe for the BSD (macOS) stat dialect first. GNU stat accepts -f but uses it
  # for filesystem output and still emits to stdout on a bad directive, so a
  # `stat -f … || stat -c …` chain would concatenate that junk with the fallback
  # and leave $perm non-numeric — which would silently skip the check on Linux.
  if stat -f '%Lp' /dev/null >/dev/null 2>&1; then
    perm="$(stat -f '%Lp' "$f")"
  else
    perm="$(stat -c '%a' "$f")"
  fi
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
  [[ -n "${RUNPOD_API_KEY:-}" || -n "${RUNPOD_API_KEY_FILE:-}" ]] || _auth "RUNPOD_API_KEY unset — add it to .env (console > Settings > API Keys), or set RUNPOD_API_KEY_FILE"
}

rp::require_s3_creds() {
  [[ -n "${RUNPOD_S3_ACCESS_KEY:-}" ]] || _auth "RUNPOD_S3_ACCESS_KEY unset — create an S3 API key (console > Settings > S3 API Keys)"
  [[ -n "${RUNPOD_S3_SECRET_KEY:-}" ]] || _auth "RUNPOD_S3_SECRET_KEY unset — create an S3 API key (console > Settings > S3 API Keys)"
}

rp::require_cmd() {
  command -v "$1" >/dev/null 2>&1 || rp::usage "required command not found: $1"
}

# Extract the `id` field from a create/list response body, or die with a clear error.
# Arguments:
#   $1 - out: caller's variable name (nameref) to receive the id
#   $2 - body: the JSON response body
#   $3 - label: noun for the error message (e.g. "endpoint")
# Returns:
#   0 - id extracted into $1
#   1 - no id present in body (dies via rp::die)
# Must run in the main shell so the rp::die exit propagates — unlike
# `$(rp::extract_id …)`, which would swallow it inside a command substitution.
rp::extract_id() {
  local -n extract_id_out="$1"
  local body="$2" label="$3"
  extract_id_out="$(printf '%s' "$body" | jq -r '.id // empty')"
  [[ -n "$extract_id_out" ]] || rp::die "$label create returned no id: $body"
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
  for c in jq curl awk head paste; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  ((${#missing[@]})) || return 0
  rp::usage "missing required commands: ${missing[*]} (install via your package manager)"
}

# Verb output policy: with --json print $1 verbatim (raw API JSON); otherwise
# run the remaining args as the human-mode formatter command. Single-line human
# paths inline their command (rp::ok / rp::table / rp::json_pretty); multi-line
# formatters live in named _<cmd>_<verb>_human functions in the command module.
rp::emit_json_or() {
  local json="$1"
  shift
  if rp::args_has json; then
    printf '%s\n' "$json"
    return 0
  fi
  "$@"
}

# Column-aligned table renderer. Pure jq (no column(1)) so output is portable
# across macOS/Linux/BSD. Numeric columns right-align; on a TTY with NO_COLOR
# unset the header is bold and status tokens are tinted. --json is handled
# upstream by rp::emit_json_or, not here.
# Arguments:
#   $1      - json: payload to table (array, or object wrapping one)
#   $2..    - columns: column names to extract in order; missing values render empty
#   --reshape <jq>  remap the payload before tabling (rename / nest / coerce / sort)
#   --color         force ANSI colour on
#   --no-color      force ANSI colour off
# Returns:
#   0 - always (a null payload prints the header row alone)
#   1 - malformed --reshape filter (fails loud rather than a blank table)
rp::table() {
  local json="$1"
  shift
  local reshape='.' color_mode=auto
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
    --reshape)
      reshape="$2"
      shift 2
      ;;
    --color)
      color_mode=on
      shift
      ;;
    --no-color)
      color_mode=off
      shift
      ;;
    *) break ;;
    esac
  done
  local cols=("$@")

  local body
  body="$(printf '%s' "$json" | jq -c 'if . == null then [] else . end' | jq -c "$reshape")" || return 1

  # Colour gate: on for a TTY stdout unless NO_COLOR is set, or forced via flags.
  local c_on=0
  case "$color_mode" in
  on) c_on=1 ;;
  off) c_on=0 ;;
  *) [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && c_on=1 ;;
  esac
  local c_bold='' c_red='' c_grn='' c_yel='' c_rst=''
  if ((c_on)); then
    c_bold=$'\033[1m'
    c_red=$'\033[31m'
    c_grn=$'\033[32m'
    c_yel=$'\033[33m'
    c_rst=$'\033[0m'
  fi

  # Inlined `jq -R . | jq -sc .` (rather than rp::json_array) to keep common.sh
  # free of a dependency on lib/json.sh; this is the lowest-level renderer.
  printf '%s' "$body" | jq -r --argjson fields "$(printf '%s\n' "${cols[@]}" | jq -R . | jq -sc .)" \
    --arg c_bold "$c_bold" --arg c_red "$c_red" --arg c_grn "$c_grn" --arg c_yel "$c_yel" --arg c_rst "$c_rst" '
  def colorize($col; $v):
    if ($col == "GPUS" and $v == "0") then $c_red + $v + $c_rst
    elif ($v == "LOW" or $v == "NONE" or $v == "UNAVAILABLE" or $v == "DEPLETED" or $v == "THROTTLED" or $v == "unhealthy") then $c_red + $v + $c_rst
    elif ($v == "HIGH" or $v == "AVAILABLE" or $v == "yes" or $v == "READY" or $v == "ACTIVE" or $v == "healthy") then $c_grn + $v + $c_rst
    elif ($v == "MEDIUM" or $v == "WARNING") then $c_yel + $v + $c_rst
    else $v end;
  (if . == null then [] else . end) as $data
  | ($fields | map(tostring)) as $heads
  | ($data | map([ $fields[] as $f | ((.[$f] // "") | tostring) ])) as $rows
  | ($heads | length) as $n
  | [ range(0;$n) ] as $ci
  # Column width = widest of the header cell and the values beneath it.
  | ($ci | map(. as $c | ([$heads[$c]] + [$rows[][$c]] | map(length) | max // 0))) as $w
  # A column right-aligns only when every non-empty value parses as a number.
  | ($ci | map(. as $c | ([$rows[][$c]] | map(select(length > 0)) | if length == 0 then false else all(test("^[-+]?[0-9]+(\\.[0-9]+)?$")) end))) as $num
  | (($ci | map(. as $c | ($c_bold + $heads[$c] + $c_rst) + (" " * (($w[$c]) - ($heads[$c] | length))))) | join("  ") | sub(" +$"; ""))
  , ($rows | map(. as $r | ($ci | map(. as $c | ($r[$c]) as $v | (($w[$c]) - ($v | length)) as $pad | if $num[$c] then (" " * $pad) + colorize($heads[$c]; $v) else colorize($heads[$c]; $v) + (" " * $pad) end) | join("  ") | sub(" +$"; ""))))[]'
}

# Unwrap a v2 list response that is wrapped in a single named array key
# (e.g. {"pods":[...]} -> [...]). When $2 is omitted or "-", read the JSON from
# stdin. Arrays and bare objects pass through unchanged, so single GET/POST/DELETE
# responses (object or empty) are unaffected.
rp::unwrap() {
  local key="$1" json="${2:-}"
  [[ -n "$json" && "$json" != "-" ]] || json="$(cat)"
  printf '%s' "$json" | jq -c --arg k "$key" '
    if type == "array" then .
    elif type == "object" and (has($k) and (.[$k] | type) == "array") then .[$k]
    else . end'
}
