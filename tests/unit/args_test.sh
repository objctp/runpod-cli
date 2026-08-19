#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  eval "$_opts"
}

function test_should_parse_value_when_long_flag_given() {
  rp::args_parse --name foo --size 5
  assert_equals "foo" "$(rp::args_get name)"
  assert_equals "5" "$(rp::args_get size)"
}

function test_should_parse_value_when_equals_form_given() {
  rp::args_parse --name=bar
  assert_equals "bar" "$(rp::args_get name)"
}

function test_should_keep_only_first_positional_when_multiple_given() {
  rp::args_parse create volname
  assert_equals "create" "$(rp::args_pos)"
}

function test_should_collect_all_positionals_in_order() {
  rp::args_parse ep_1 job_2 tail
  assert_equals "ep_1" "$(rp::args_pos_at 0)"
  assert_equals "job_2" "$(rp::args_pos_at 1)"
  assert_equals "tail" "$(rp::args_pos_at 2)"
  assert_equals "" "$(rp::args_pos_at 3)"
}

function test_should_require_positional_at_index() {
  local id job
  rp::args_parse ep_1 job_2
  rp::require_pos_at 0 id "usage: rp serverless status <id> <jobId>"
  rp::require_pos_at 1 job "usage: rp serverless status <id> <jobId>"
  assert_equals "ep_1" "$id"
  assert_equals "job_2" "$job"
}

function test_should_exit_two_when_require_pos_at_missing() {
  rp::args_parse ep_1
  (
    local job
    rp::require_pos_at 1 job "usage: rp serverless status <id> <jobId>" >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_set_bool_when_known_bool_flag_given() {
  rp::args_parse --json
  assert_equals "1" "$(rp::args_get json)"
}

function test_should_return_default_when_flag_missing() {
  rp::args_parse
  assert_equals "def" "$(rp::args_get missing def)"
}

function test_should_return_uint_when_value_valid() {
  rp::args_parse --size 5
  assert_equals "5" "$(rp::args_get_uint size)"
}

function test_should_return_default_uint_when_flag_missing() {
  rp::args_parse
  assert_equals "0" "$(rp::args_get_uint size 0)"
}

function test_should_die_when_uint_value_invalid() {
  rp::args_parse --size abc
  (rp::args_get_uint size >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_assign_bool_when_value_valid() {
  local v
  rp::args_parse --locked true
  rp::require_bool v locked
  assert_equals "true" "$v"
}

function test_should_assign_empty_when_bool_flag_missing() {
  local v
  rp::args_parse
  rp::require_bool v locked
  assert_empty "$v"
}

function test_should_die_when_bool_value_invalid() {
  rp::args_parse --locked maybe
  (
    local v
    rp::require_bool v locked >/dev/null 2>&1
  )
  assert_exit_code 2
}

# main-shell variants (bashunit skips lines run inside $(...)) so rp::args_get_uint
# registers coverage.
function test_should_return_uint_main_shell_when_value_valid() {
  local tmp
  tmp="$(mktemp)"
  rp::args_parse --size 5
  rp::args_get_uint size >"$tmp"
  assert_equals "5" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_return_default_uint_main_shell_when_flag_missing() {
  local tmp
  tmp="$(mktemp)"
  rp::args_parse
  rp::args_get_uint size 0 >"$tmp"
  assert_equals "0" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_split_lines_when_csv_given() {
  assert_equals "$(printf 'a\nb\nc')" "$(rp::split_csv "a,b,c")"
}

function test_should_accumulate_when_repeatable_flag_repeated() {
  rp::args_parse --env A=1 --env B=2
  assert_equals "$(printf 'A=1\nB=2')" "$(rp::args_get env)"
}

function test_should_accumulate_when_repeatable_flag_equals_form_repeated() {
  rp::args_parse --env=A=1 --env=B=2
  assert_equals "$(printf 'A=1\nB=2')" "$(rp::args_get env)"
}

function test_should_keep_csv_form_for_repeatable_flag() {
  rp::args_parse --env A=1,B=2
  assert_equals "A=1,B=2" "$(rp::args_get env)"
}

function test_should_overwrite_when_non_repeatable_flag_repeated() {
  rp::args_parse --name foo --name bar
  assert_equals "bar" "$(rp::args_get name)"
}

function test_should_assign_positional_when_require_pos_given() {
  local id
  rp::args_parse pod-123
  rp::require_pos id "usage: rp pod get <id>"
  assert_equals "pod-123" "$id"
}

function test_should_exit_two_when_require_pos_missing() {
  rp::args_parse --json
  (
    local id
    rp::require_pos id "usage: rp pod get <id>" >/dev/null 2>&1
  )
  assert_exit_code 2
}

function test_should_print_usage_when_require_pos_missing() {
  rp::args_parse
  local err
  err="$(
    local id
    rp::require_pos id "usage: rp pod get <id>" 2>&1 >/dev/null || true
  )"
  assert_equals "usage: rp pod get <id>" "$err"
}

# main-shell variants (bashunit skips lines run inside $(...)) so rp::args_pos
# and rp::split_csv register coverage.
function test_should_return_positional_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::args_parse create volname
  rp::args_pos >"$tmp"
  assert_equals "create" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_split_csv_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::split_csv "a,b,c" >"$tmp"
  assert_equals "$(printf 'a\nb\nc')" "$(<"$tmp")"
  rm -f "$tmp"
}
