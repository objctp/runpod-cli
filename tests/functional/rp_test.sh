#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # bin/rp resolves RP_ROOT from BASH_SOURCE and re-sources every lib; its main
  # block is guarded (BASH_SOURCE[0]==${0}) so sourcing here is side-effect free.
  source "$RP_ROOT/bin/rp"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  ERR="$(mktemp)"
}

function tear_down() {
  rm -f "$OUT" "$ERR"
}

function test_should_print_help_when_help_called() {
  _help >"$OUT"
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "Usage: rp" "$rendered"
  assert_contains "Resources:" "$rendered"
}

function test_should_print_help_when_no_args_given() {
  rp::main >"$OUT" 2>/dev/null
  assert_contains "Usage: rp" "$(<"$OUT")"
}

function test_should_print_help_when_dash_dash_help_given() {
  rp::main --help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp" "$(<"$OUT")"
}

function test_should_confirm_rest_auth_when_ping_called() {
  rp::http() { :; }
  rp::main _ping >/dev/null 2>"$ERR"
  rp::http() { :; }
  assert_contains "REST auth works" "$(<"$ERR")"
}

function test_should_exit_two_when_resource_unknown() {
  (rp::main __no_such_resource__ >/dev/null 2>&1)
  assert_exit_code 2
}

# L1: a crafted resource name (path traversal) must be rejected before any file
# is sourced — it must never reach `. "$cmd"`.
function test_should_reject_traversal_resource_name() {
  (rp::main '../../../tmp/evil' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_reject_glob_resource_name() {
  (rp::main 'pod;' >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_dispatch_to_command_when_resource_known() {
  rp::main stock --help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp stock" "$(<"$OUT")"
}

# Hyphenated resource files map to underscored entry functions
# (cost-center -> rp::cmd_cost_center).
function test_should_dispatch_hyphenated_resource() {
  RP_COST_CENTERS_FILE="$(mktemp -u)"
  rp::main cost-center --help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp cost-center" "$(<"$OUT")"
  rm -f "$RP_COST_CENTERS_FILE"
}

function test_should_print_version_when_version_called() {
  rp::main version >"$OUT" 2>/dev/null
  assert_not_empty "$(<"$OUT")"
}

function test_should_print_version_when_dash_v_given() {
  rp::main -v >"$OUT" 2>/dev/null
  assert_not_empty "$(<"$OUT")"
}

# The hidden grammar-spec verb (consumed by the completion generator) emits
# TSV through rp::main like any other dispatch, and returns 0.
function test_should_emit_completion_spec_when_complete_spec_called() {
  rp::main _complete-spec >"$OUT" 2>"$ERR"
  assert_equals "0" "$?"
  local spec
  spec="$(<"$OUT")"
  assert_contains $'v\tpod\tcreate' "$spec"
  assert_contains $'f\tpod\tcreate\tgpu\tvalue\t' "$spec"
}

# The hidden dynamic-completion verb: arity is enforced (usage exit 2 in a
# subshell), unknown targets stay silent with exit 0 — completion must never
# surface errors at TAB time.
function test_should_enforce_complete_arity_and_stay_silent() {
  (rp::main _complete >/dev/null 2>&1)
  assert_exit_code 2
  (rp::main _complete pod >/dev/null 2>&1)
  assert_exit_code 2
  out="$(rp::main _complete hub search - 2>/dev/null)"
  assert_equals "" "$out"
}
