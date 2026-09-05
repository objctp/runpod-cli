#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/auth.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  unset RUNPOD_API_KEY RUNPOD_API_KEY_FILE
}

function tear_down() {
  rm -f "$OUT"
}

function test_token_from_env() {
  RUNPOD_API_KEY="sk-env123" rp::auth_token >"$OUT"
  assert_equals "sk-env123" "$(<"$OUT")"
}

function test_header_format_from_env() {
  RUNPOD_API_KEY="sk-env123" rp::auth_header >"$OUT"
  assert_equals "Authorization: Bearer sk-env123" "$(<"$OUT")"
}

function test_token_from_file_trims_newline() {
  local f
  f="$(mktemp)"
  printf 'sk-file456\n' >"$f"
  RUNPOD_API_KEY_FILE="$f" rp::auth_token >"$OUT"
  assert_equals "sk-file456" "$(<"$OUT")"
  rm -f "$f"
}

# A CRLF-written secret file must not embed \r in the Bearer token (opaque 401s).
function test_token_from_file_strips_carriage_returns() {
  local f
  f="$(mktemp)"
  printf 'sk-crlf789\r\n' >"$f"
  RUNPOD_API_KEY_FILE="$f" rp::auth_token >"$OUT"
  assert_equals "sk-crlf789" "$(<"$OUT")"
  rm -f "$f"
}

# The account store's permission refusal must reach the user: _load_account is
# called without stderr suppression, so a group/world-writable account file
# dies LOUDLY (message + exit 1), not silently. _rp_env_load lives in bin/rp
# (unsourceable), so a faithful stub of its refusal is defined — and unset —
# inside this test only; without it _load_account is a no-op here.
function test_world_writable_account_file_dies_loudly() {
  _rp_env_load() {
    local f="$1" perm
    [[ -f "$f" ]] || return 0
    if stat -f '%Lp' /dev/null >/dev/null 2>&1; then
      perm="$(stat -f '%Lp' "$f")"
    else
      perm="$(stat -c '%a' "$f")"
    fi
    if [[ "$perm" =~ ^[0-7]+$ ]] && ((8#$perm & 022)); then
      rp::die "$f is group/world-writable (mode $perm); refusing to load it — run 'chmod go-w $f'"
    fi
    return 0
  }
  local dir f out rc saved_account saved_creds saved_active
  saved_account="${RP_ACCOUNT:-}" saved_creds="$RP_CREDS_DIR" saved_active="$RP_ACTIVE_FILE"
  dir="$(mktemp -d)"
  f="$dir/acme"
  printf 'RUNPOD_API_KEY=sk-acme\n' >"$f"
  chmod 666 "$f"
  unset RUNPOD_API_KEY RUNPOD_API_KEY_FILE
  RP_ACCOUNT=acme RP_CREDS_DIR="$dir" RP_ACTIVE_FILE="$dir/active"
  out="$(rp::auth_token 2>&1)"
  rc=$?
  RP_ACCOUNT="$saved_account" RP_CREDS_DIR="$saved_creds" RP_ACTIVE_FILE="$saved_active"
  chmod 600 "$f"
  rm -rf "$dir"
  unset -f _rp_env_load
  assert_contains "group/world-writable" "$out"
  assert_equals "1" "$rc"
}

function test_file_missing_dies() {
  local out
  out="$(
    RUNPOD_API_KEY_FILE=/no/such/file rp::auth_token 2>&1
    echo "exit=$?"
  )"
  assert_contains "missing file" "$out"
}

function test_no_source_dies_with_auth_exit() {
  local out rc
  out="$(rp::auth_token 2>&1)"
  rc=$?
  assert_contains "RUNPOD_API_KEY unset" "$out"
  assert_equals "3" "$rc"
}

# L2: with `set -x` (bash -x), the token must not appear in the trace. Capture
# stderr (the trace) only — stdout (the token) is discarded.
function test_should_not_leak_token_in_xtrace_via_auth_token() {
  local err
  export RUNPOD_API_KEY="sk-secret-xyz"
  err="$( (
    set -x
    rp::auth_token
  ) 2>&1 >/dev/null)"
  assert_not_contains "sk-secret-xyz" "$err"
}

function test_should_not_leak_token_in_xtrace_via_auth_header() {
  local err
  export RUNPOD_API_KEY="sk-secret-xyz"
  err="$( (
    set -x
    rp::auth_header
  ) 2>&1 >/dev/null)"
  assert_not_contains "sk-secret-xyz" "$err"
}
