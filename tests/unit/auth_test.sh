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
