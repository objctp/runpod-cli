#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/paginate.sh"
  source "$RP_ROOT/commands/api.sh"
  eval "$_opts"
}

API_FIXTURE='{"pods":[{"id":"p1","name":"alpha"}]}'

function set_up() {
  OUT="$(mktemp)"
  # Doubles record into a file (not a global) because bashunit runs each test
  # in a subshell — globals set inside the call are lost when it returns.
  API_CAP="$(mktemp)"
  rp::http() {
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$API_CAP"
    printf '%s' "$API_FIXTURE"
  }
  rp::http_api() {
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$API_CAP"
    printf '%s' "$API_FIXTURE"
  }
}

function tear_down() {
  rm -f "$OUT" "$API_CAP"
}

# $1 expected "<method>\t<path>\t<body>"; reads the single recorded call.
function assert_call() {
  assert_equals "$1" "$(<"$API_CAP")"
}

function test_should_dispatch_rest_plane_by_default() {
  rp::cmd_api GET /pods >"$OUT"
  assert_equals "$API_FIXTURE" "$(<"$OUT")"
  assert_call $'GET\t/pods\t'
}

function test_should_accept_path_without_leading_slash() {
  rp::cmd_api GET pods >"$OUT"
  assert_call $'GET\t/pods\t'
}

function test_should_dispatch_api_plane_to_http_api() {
  rp::cmd_api POST /e1/runsync --plane api --body '{"x":1}' >"$OUT"
  assert_call $'POST\t/e1/runsync\t{"x":1}'
}

function test_should_apply_jq_filter() {
  local out
  out="$(rp::cmd_api GET /pods --jq '.pods[].id')"
  assert_equals "p1" "$out"
}

function test_should_read_body_from_file() {
  local f
  f="$(mktemp)"
  printf '{"name":"fromfile"}' >"$f"
  rp::cmd_api POST /pods --body "@$f" >"$OUT"
  assert_call $'POST\t/pods\t{"name":"fromfile"}'
  rm -f "$f"
}

function test_should_error_on_unknown_plane() {
  local out
  out="$(rp::cmd_api GET /pods --plane bad 2>&1)"
  assert_contains "unknown --plane" "$out"
}
