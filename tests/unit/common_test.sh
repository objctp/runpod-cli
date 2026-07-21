#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Re-establish the real common helpers even if an earlier test file sourced
  # lib/common.sh (setting its guard).
  unset _RP_COMMON
  source "$RP_ROOT/lib/common.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
}

function tear_down() {
  rm -f "$OUT"
}

# --- output helpers (stderr) ---

function test_should_print_message_when_info_called() {
  local err
  err="$(rp::info hello-world 2>&1 >/dev/null)"
  assert_equals "hello-world" "$err"
}

function test_should_print_message_when_warn_called() {
  local err
  err="$(rp::warn careful 2>&1 >/dev/null)"
  assert_equals "careful" "$err"
}

function test_should_print_message_when_ok_called() {
  local err
  err="$(rp::ok "done" 2>&1 >/dev/null)"
  assert_equals "done" "$err"
}

# --- exiters (distinct exit codes) ---

function test_should_exit_one_when_die_called() {
  (rp::die boom >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_print_message_when_die_called() {
  local err
  err="$(rp::die boom 2>&1 >/dev/null)"
  assert_equals "boom" "$err"
}

function test_should_exit_two_when_usage_called() {
  (rp::usage "bad args" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_four_when_notfound_called() {
  (rp::notfound "no such thing" >/dev/null 2>&1)
  assert_exit_code 4
}

# --- require_* guards ---

function test_should_pass_when_api_key_set() {
  RUNPOD_API_KEY="sk-test"
  rp::require_api_key
  assert_successful_code "$?"
}

function test_should_exit_three_when_api_key_unset() {
  unset RUNPOD_API_KEY
  (rp::require_api_key >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_pass_when_s3_creds_set() {
  RUNPOD_S3_ACCESS_KEY="ak"
  RUNPOD_S3_SECRET_KEY="sk"
  rp::require_s3_creds
  assert_successful_code "$?"
}

function test_should_exit_three_when_s3_access_key_unset() {
  unset RUNPOD_S3_ACCESS_KEY
  RUNPOD_S3_SECRET_KEY="sk"
  (rp::require_s3_creds >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_exit_three_when_s3_secret_key_unset() {
  RUNPOD_S3_ACCESS_KEY="ak"
  unset RUNPOD_S3_SECRET_KEY
  (rp::require_s3_creds >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_pass_when_required_cmd_present() {
  rp::require_cmd jq
  assert_successful_code "$?"
}

function test_should_exit_two_when_required_cmd_missing() {
  (rp::require_cmd __no_such_tool__ >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_pass_when_uint_is_valid() {
  rp::require_uint 5 size
  assert_successful_code "$?"
}

function test_should_pass_when_uint_is_empty() {
  rp::require_uint "" size
  assert_successful_code "$?"
}

function test_should_exit_two_when_uint_is_invalid() {
  (rp::require_uint abc size >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_pass_when_core_tools_present() {
  rp::check_core
  assert_successful_code "$?"
}

# --- rp::table ---

function test_should_render_header_and_rows_when_table_given() {
  rp::table '[{"id":"a","name":"x"},{"id":"b","name":"y"}]' id name >"$OUT"
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "id" "$rendered"
  assert_contains "name" "$rendered"
  assert_contains "a" "$rendered"
  assert_contains "y" "$rendered"
}

function test_should_render_header_only_when_table_input_null() {
  rp::table 'null' id name >"$OUT"
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "id" "$rendered"
  assert_line_count 1 "$rendered"
}

function test_should_render_empty_cell_when_field_missing() {
  rp::table '[{"id":"a"}]' id name >"$OUT"
  assert_contains "a" "$(<"$OUT")"
}

# --- _warn_if_world_readable ---

function test_should_stay_silent_when_file_is_private() {
  local f err
  f="$(mktemp)"
  chmod 600 "$f"
  err="$(_warn_if_world_readable "$f" 2>&1 >/dev/null)"
  assert_empty "$err"
  rm -f "$f"
}

function test_should_warn_when_file_is_world_readable() {
  local f err
  f="$(mktemp)"
  chmod 644 "$f"
  err="$(_warn_if_world_readable "$f" 2>&1 >/dev/null)"
  assert_contains "world-readable" "$err"
  rm -f "$f"
}

# Regression: a private .env (mode 600) made the bare call under `set -e` abort
# rp entirely. The helper must return 0 even when it has nothing to warn about.
function test_should_return_zero_when_file_is_private() {
  local f
  f="$(mktemp)"
  chmod 600 "$f"
  _warn_if_world_readable "$f"
  assert_successful_code "$?"
  rm -f "$f"
}

# --- _mktemp / _tmp_cleanup ---

function test_should_register_and_remove_temp_when_cleanup_runs() {
  local t1
  _mktemp t1
  assert_file_exists "$t1"
  _tmp_cleanup
  assert_file_not_exists "$t1"
}

function test_should_noop_when_cleanup_runs_with_no_temps() {
  _tmp_cleanup
  assert_successful_code "$?"
}
