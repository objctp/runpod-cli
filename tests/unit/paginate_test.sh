#!/usr/bin/env bash
# Unit tests for lib/paginate.sh — the client-side --limit/--cursor slicing and
# the "next cursor" stderr hint. rp::paginate takes an array nameref and reads
# RP_ARGS, so each test parses its flags then calls it in the main shell.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/paginate.sh"
  eval "$_opts"
}

function set_up() {
  PAGES='["a","b","c","d"]'
}

function _run_paginate() {
  local err
  err="$(rp::args_parse "$@" && rp::paginate PAGES 2>&1 >/dev/null)"
  printf '%s' "$err"
}

function test_hint_prints_when_limit_truncates() {
  local err
  err="$(_run_paginate --limit 2)"
  assert_contains "more items available — next cursor: 2 (total 4)" "$err"
}

function test_hint_names_the_skipped_offset_as_next_cursor() {
  local err
  err="$(_run_paginate --limit 1 --cursor 2)"
  assert_contains "next cursor: 3 (total 4)" "$err"
}

function test_no_hint_when_limit_zero() {
  local err
  err="$(_run_paginate --limit 0)"
  assert_not_contains "next cursor" "$err"
}

function test_no_hint_when_page_covers_the_whole_list() {
  local err
  err="$(_run_paginate --limit 4)"
  assert_not_contains "next cursor" "$err"
}

function test_no_hint_when_limit_exceeds_the_list() {
  local err
  err="$(_run_paginate --limit 99)"
  assert_not_contains "next cursor" "$err"
}

function test_no_hint_when_cursor_sits_past_the_end() {
  local err
  err="$(_run_paginate --limit 2 --cursor 9)"
  assert_not_contains "next cursor" "$err"
}

function test_limit_zero_leaves_the_array_untouched() {
  rp::args_parse --limit 0
  rp::paginate PAGES
  assert_equals '["a","b","c","d"]' "$PAGES"
}
