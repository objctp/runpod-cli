#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/commands/account.sh"
  eval "$_opts"
}

function test_should_render_balance_and_spend() {
  rp::graphql() {
    printf '{"myself":{"id":"user_abc","clientBalance":10,"spendLimit":80,"currentSpendPerHr":0}}'
  }
  rp::args_parse
  local out
  out="$(_account_info 2>/dev/null)"
  assert_contains "user_abc" "$out"
  assert_contains "\$10" "$out"
  assert_contains "\$80" "$out"
  rp::graphql() { :; }
}

function test_should_emit_raw_json_when_json_flag_set() {
  rp::graphql() {
    printf '{"myself":{"id":"user_abc","clientBalance":10,"spendLimit":80,"currentSpendPerHr":0}}'
  }
  rp::args_parse --json
  local out
  out="$(_account_info 2>/dev/null)"
  assert_contains '"clientBalance":10' "$out"
  rp::graphql() { :; }
}

# main-shell dispatcher call (bashunit skips lines run inside $(...)) so the
# public rp::cmd_account entry + help branch register coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_account help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp account" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing: the info verb (and the no-arg default) both hit _account_info.
function test_should_route_info_verb() {
  local cap
  cap="$(mktemp)"
  rp::graphql() {
    printf '%s' "$1" >"$cap"
    printf '{"myself":{"id":"u","clientBalance":0,"spendLimit":0,"currentSpendPerHr":0}}'
  }
  rp::cmd_account info >/dev/null 2>&1
  assert_contains "myself" "$(<"$cap")"
  rp::cmd_account >/dev/null 2>&1
  assert_contains "myself" "$(<"$cap")"
  rm -f "$cap"
}
