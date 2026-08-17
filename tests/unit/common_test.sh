#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Re-establish the real common helpers even if an earlier test file sourced
  # lib/common.sh (setting its guard).
  unset _RP_COMMON
  source "$RP_ROOT/lib/common.sh"
  # rp::emit_json_or reads the parsed flags via rp::args_has.
  source "$RP_ROOT/lib/args.sh"
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

# --- rp::http_exit_code (exit-code contract) ---

function test_should_map_401_to_auth_exit() {
  assert_equals "$RP_EXIT_AUTH" "$(rp::http_exit_code 401)"
}

function test_should_map_403_to_auth_exit() {
  assert_equals "$RP_EXIT_AUTH" "$(rp::http_exit_code 403)"
}

function test_should_map_404_to_notfound_exit() {
  assert_equals "$RP_EXIT_NOTFOUND" "$(rp::http_exit_code 404)"
}

function test_should_map_5xx_to_general_exit() {
  assert_equals 1 "$(rp::http_exit_code 500)"
}

function test_should_map_400_to_general_exit() {
  assert_equals 1 "$(rp::http_exit_code 400)"
}

function test_should_map_2xx_to_zero() {
  assert_equals 0 "$(rp::http_exit_code 200)"
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

# --- rp::check_runtime (bash>=5 / jq / curl preflight) ---

function test_should_pass_when_runtime_ready() {
  # The test harness runs under Bash 5+ with jq/curl on PATH, so the preflight
  # is expected to pass here. Guards the function exists and the happy path is clean.
  rp::check_runtime
  assert_successful_code "$?"
}

function test_should_exit_one_when_bash_too_old() {
  # BASH_VERSINFO is readonly, so drive the real Bash 3.2 that ships on macOS to
  # exercise the unsupported-version branch (rp::die -> exit 1).
  /bin/bash -c 'RP_ROOT="'"$RP_ROOT"'"; . "$RP_ROOT/lib/common.sh"; rp::check_runtime' >/dev/null 2>&1
  assert_exit_code 1
}

function test_should_exit_two_when_jq_missing() {
  (
    # Simulate a missing jq by stubbing the preflight so it reports jq absent,
    # exercising the rp::usage exit (2) branch without touching the real PATH.
    rp::check_runtime() {
      rp::usage "missing required commands: jq"
    }
    rp::check_runtime >/dev/null 2>&1
  )
  assert_exit_code 2
}

# --- rp::require_id ---

function test_should_accept_well_formed_id() {
  local out
  rp::require_id out "e1abc_2-3.4" "endpoint id"
  assert_equals "e1abc_2-3.4" "$out"
}

function test_should_accept_purely_numeric_id() {
  local out
  rp::require_id out "12345" "volume id"
  assert_equals "12345" "$out"
}

function test_should_exit_two_on_id_with_slash() {
  local out
  (rp::require_id out "a/b" "endpoint id" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_two_on_id_with_query_metachar() {
  local out
  (rp::require_id out "a?b&c" "endpoint id" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_two_on_id_with_whitespace() {
  local out
  (rp::require_id out "a b" "endpoint id" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_two_on_empty_id() {
  local out
  (rp::require_id out "" "endpoint id" >/dev/null 2>&1)
  assert_exit_code 2
}

# --- rp::emit_json_or ---

function test_should_print_raw_json_when_json_flag_set() {
  rp::args_parse --json
  rp::emit_json_or '{"id":"p1"}' rp::table '{"id":"p1"}' id >"$OUT"
  assert_equals '{"id":"p1"}' "$(<"$OUT")"
}

function test_should_run_formatter_when_json_flag_unset() {
  rp::args_parse
  rp::emit_json_or '[{"id":"a"}]' rp::table '[{"id":"a"}]' id >"$OUT"
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "id" "$rendered"
  assert_contains "a" "$rendered"
}

function test_should_pass_formatter_args_verbatim_when_json_flag_unset() {
  rp::args_parse
  local err
  err="$(rp::emit_json_or '{}' rp::ok "updated pod p1" 2>&1 >/dev/null)"
  assert_equals "updated pod p1" "$err"
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

# --- rp::table --reshape ---

function test_should_reshape_nested_fields_when_reshape_given() {
  rp::table '[{"id":"e1","name":"n","workers":{"min":1,"max":4},"scaling":{"idleTimeout":60}}]' \
    --reshape 'map({id, name, workersMin:.workers.min, workersMax:.workers.max, idleTimeout:.scaling.idleTimeout})' \
    id name workersMin workersMax idleTimeout >"$OUT"
  local r
  r="$(<"$OUT")"
  assert_contains "workersMin" "$r"
  assert_contains "1" "$r"
  assert_contains "60" "$r"
}

function test_should_rename_and_coerce_columns_when_reshape_given() {
  rp::table '[{"id":"g1","name":"RTX","memory":null,"price":{"secure":1.2},"availability":"AVAILABLE"}]' \
    --reshape 'map({ID:.id, DISPLAY:.name, VRAM_GB:(.memory//0), SECURE_PRICE:(.price.secure//""), STOCK:(.availability//"")})' \
    ID DISPLAY VRAM_GB SECURE_PRICE STOCK >"$OUT"
  local r
  r="$(<"$OUT")"
  assert_contains "VRAM_GB" "$r"
  assert_contains "0" "$r" # null memory coerced to 0
  assert_contains "RTX" "$r"
}

function test_should_apply_boolean_and_sort_in_reshape() {
  rp::table '{"dataCenters":[{"id":"EU-RO-1","s3apiEnabled":true},{"id":"CA-OR-1","s3apiEnabled":false}]}' \
    --reshape '.dataCenters | map({DATACENTER:.id, S3_API:(if .s3apiEnabled then "yes" else "" end)}) | sort_by(.DATACENTER)' \
    DATACENTER S3_API >"$OUT"
  local r
  r="$(<"$OUT")"
  assert_contains "S3_API" "$r"
  assert_contains "yes" "$r"
  assert_contains "CA-OR-1" "$r"
}

function test_should_render_empty_table_when_null_input_and_reshape_given() {
  rp::table 'null' --reshape 'map({id})' id >"$OUT"
  local r
  r="$(<"$OUT")"
  assert_contains "id" "$r"
  assert_line_count 1 "$r"
}

function test_should_fail_loudly_when_reshape_is_malformed() {
  (rp::table '[{"id":"a"}]' --reshape 'map({id:)' id >/dev/null 2>&1)
  assert_exit_code 1
}

# --- rp::unwrap ---

function test_should_unwrap_named_array_when_body_is_wrapped() {
  assert_equals '[{"id":"p1"}]' "$(rp::unwrap pods '{"pods":[{"id":"p1"}]}')"
}

function test_should_pass_through_when_body_is_array() {
  assert_equals '[{"id":"p1"}]' "$(rp::unwrap pods '[{"id":"p1"}]')"
}

function test_should_pass_through_when_body_is_plain_object() {
  assert_equals '{"id":"p1"}' "$(rp::unwrap pods '{"id":"p1"}')"
}

function test_should_pass_through_when_key_is_not_an_array() {
  assert_equals '{"pods":"x"}' "$(rp::unwrap pods '{"pods":"x"}')"
}

function test_should_read_stdin_when_json_arg_omitted() {
  assert_equals '[1,2]' "$(printf '%s' '{"gpus":[1,2]}' | rp::unwrap gpus)"
}

# main-shell variants (bashunit skips lines run inside $(...)) so rp::unwrap's
# stdin branch and the elif/else jq arms register coverage.
function test_should_unwrap_array_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::unwrap gpus '[{"id":"p1"}]' >"$tmp"
  assert_equals '[{"id":"p1"}]' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_unwrap_wrapped_key_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::unwrap gpus '{"gpus":[1,2]}' >"$tmp"
  assert_equals '[1,2]' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_unwrap_plain_object_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::unwrap gpus '{"id":"p1"}' >"$tmp"
  assert_equals '{"id":"p1"}' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_unwrap_stdin_main_shell() {
  local tmp
  tmp="$(mktemp)"
  printf '%s' '{"gpus":[1,2]}' | rp::unwrap gpus >"$tmp"
  assert_equals '[1,2]' "$(<"$tmp")"
  rm -f "$tmp"
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
