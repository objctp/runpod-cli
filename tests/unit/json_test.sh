#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  eval "$_opts"
}

function test_should_quote_string_when_str_called() {
  assert_equals '"rp-smoke"' "$(rp::json_str "rp-smoke")"
}

function test_should_escape_quotes_when_string_has_special_chars() {
  assert_equals '"a\"b"' "$(rp::json_str 'a"b')"
}

function test_should_pretty_print_when_json_pretty_called() {
  assert_equals "$(printf '{\n  "a": 1\n}')" "$(rp::json_pretty '{"a":1}')"
}

function test_should_build_array_when_multiple_values_given() {
  assert_equals '["a","b"]' "$(rp::json_array "a" "b")"
}

function test_should_build_empty_array_when_no_values_given() {
  assert_equals '[]' "$(rp::json_array)"
}

function test_should_build_object_when_kv_pairs_given() {
  assert_equals '{"name":"x","size":5}' "$(rp::json_obj name "$(rp::json_str x)" size 5)"
}

function test_should_merge_when_two_objects_given() {
  assert_equals '{"a":1,"b":2}' "$(_json_merge '{"a":1}' '{"b":2}')"
}

function test_should_set_field_when_value_nonempty() {
  local obj='{}'
  rp::obj_set obj k '"v"'
  assert_equals '{"k":"v"}' "$obj"
}

function test_should_skip_field_when_value_empty() {
  local obj='{"a":1}'
  rp::obj_set obj b ''
  assert_equals '{"a":1}' "$obj"
}

function test_should_keep_comma_in_env_value() {
  assert_equals '{"A":"1,B=2"}' "$(rp::env_to_json "A=1,B=2")"
}

function test_should_error_on_env_with_empty_key() {
  (rp::env_to_json "=value" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_error_on_env_with_only_equals() {
  # shellcheck disable=SC2205 # subshell needed: rp::usage exits the subshell
  (rp::env_to_json "=" >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_parse_multiple_envs_when_newline_delimited() {
  assert_equals '{"A":"1","B":"2"}' "$(rp::env_to_json "$(printf 'A=1\nB=2')")"
}

function test_should_split_env_on_first_equals_only() {
  assert_equals '{"TOKEN":"a==b"}' "$(rp::env_to_json "TOKEN=a==b")"
}

function test_should_overlay_env_keeping_untouched_keys() {
  local obj='{"image":"img:1","env":{"A":"1","B":"2"}}'
  rp::obj_merge_env obj "B=9"
  assert_equals '{"A":"1","B":"9"}' "$(jq -c '.env' <<<"$obj")"
  assert_equals 'img:1' "$(jq -r '.image' <<<"$obj")"
}

function test_should_add_env_map_when_object_has_none() {
  local obj='{"image":"img:1"}'
  rp::obj_merge_env obj "$(printf 'A=1\nB=x,y=z')"
  assert_equals '{"A":"1","B":"x,y=z"}' "$(jq -c '.env' <<<"$obj")"
}

function test_should_leave_object_untouched_when_env_empty() {
  local obj='{"env":{"A":"1"}}'
  rp::obj_merge_env obj ""
  assert_equals '{"env":{"A":"1"}}' "$obj"
}

function test_should_build_jsonarray_when_csv_given() {
  assert_equals '["x","y"]' "$(rp::csv_to_jsonarray "x,y")"
}

# Named request-body shapes (C3).
function test_should_build_pod_gpu_shape() {
  assert_equals '{"id":"NVIDIA RTX 4090","count":1}' "$(rp::json_gpu_pod "NVIDIA RTX 4090" 1)"
}

function test_should_build_pod_cpu_shape() {
  assert_equals '{"id":"cpu5c","vcpuCount":4}' "$(rp::json_cpu "cpu5c" 4)"
}

function test_should_build_endpoint_gpu_shape() {
  assert_equals '{"pools":["ADA_24","ADA_48"],"count":2}' "$(rp::json_gpu_endpoint "ADA_24,ADA_48" 2)"
}

function test_should_build_endpoint_gpu_shape_with_exclusions() {
  assert_equals '{"pools":["ADA_24"],"excludedTypes":["NVIDIA L4","NVIDIA L40"],"count":2}' "$(rp::json_gpu_endpoint "ADA_24" 2 "NVIDIA L4,NVIDIA L40")"
}

function test_should_build_endpoint_gpu_shape_skipping_empty_excluded_tokens() {
  assert_equals '{"pools":["ADA_24"],"excludedTypes":["NVIDIA L4"],"count":1}' "$(rp::json_gpu_endpoint "ADA_24" 1 "NVIDIA L4,,")"
}

function test_should_quote_mig_exclusion_with_spaces() {
  assert_equals '{"pools":["AMPERE_24"],"excludedTypes":["NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"],"count":1}' "$(rp::json_gpu_endpoint "AMPERE_24" 1 "NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb")"
}

function test_should_build_workers_shape_with_both_bounds() {
  assert_equals '{"min":1,"max":10}' "$(rp::json_workers "1" "10")"
}

function test_should_build_workers_shape_with_max_only() {
  assert_equals '{"max":10}' "$(rp::json_workers "" "10")"
}

function test_should_build_workers_shape_with_min_only() {
  assert_equals '{"min":1}' "$(rp::json_workers "1" "")"
}

function test_should_build_workers_shape_with_idle_timeout() {
  assert_equals '{"min":1,"max":10,"idleTimeout":5}' "$(rp::json_workers "1" "10" "5")"
}

function test_should_build_workers_shape_skipping_empty_idle_timeout() {
  assert_equals '{"max":10}' "$(rp::json_workers "" "10" "")"
}

function test_should_build_queue_delay_scaling_arm() {
  assert_equals '{"type":"QUEUE_DELAY","queueDelay":0.5}' "$(rp::json_scaling QUEUE_DELAY 0.5)"
}

function test_should_build_request_count_scaling_arm() {
  assert_equals '{"type":"REQUEST_COUNT","requestCount":3}' "$(rp::json_scaling REQUEST_COUNT 3)"
}

function test_should_error_on_unknown_scaler_type() {
  (rp::json_scaling BOGUS 1 >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_build_nv_mount_shape() {
  assert_equals '[{"volumeId":"vol_abc","path":"/workspace"}]' "$(rp::json_nv_mount "vol_abc")"
}

function test_should_build_nv_mount_with_custom_path() {
  assert_equals '[{"volumeId":"v1","path":"/data"}]' "$(rp::json_nv_mount "v1" "/data")"
}

function test_should_build_persistent_mount_shape() {
  assert_equals '{"persistent":{"size":20,"path":"/workspace"}}' "$(rp::json_persistent_mount "20")"
}

function test_should_build_persistent_mount_with_custom_path() {
  assert_equals '{"persistent":{"size":20,"path":"/data"}}' "$(rp::json_persistent_mount "20" "/data")"
}

# v2 ContainerConfig.args is a single string, not an array.
function test_should_join_csv_into_argstring() {
  assert_equals 'python main.py --port 8080' "$(rp::csv_to_argstring "python,main.py,--port 8080")"
}

function test_should_pass_through_plain_string_in_argstring() {
  assert_equals 'sleep infinity' "$(rp::csv_to_argstring "sleep infinity")"
}

# main-shell variants (bashunit skips lines run inside $(...)) so the public json
# builders register coverage.
function test_should_quote_string_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::json_str "rp-smoke" >"$tmp"
  assert_equals '"rp-smoke"' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_build_array_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::json_array "a" "b" >"$tmp"
  assert_equals '["a","b"]' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_build_env_object_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::env_to_json "$(printf 'A=1\nB=2')" >"$tmp"
  assert_equals '{"A":"1","B":"2"}' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_build_jsonarray_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::csv_to_jsonarray "x,y" >"$tmp"
  assert_equals '["x","y"]' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_build_empty_array_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::json_array >"$tmp"
  assert_equals '[]' "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_join_csv_into_argstring_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::csv_to_argstring "python,main.py,--port 8080" >"$tmp"
  assert_equals 'python main.py --port 8080' "$(<"$tmp")"
  rm -f "$tmp"
}
