#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/paginate.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/commands/catalog.sh"
  eval "$_opts"
}

function test_list_gets_catalog_templates_and_tables() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"templates":[{"id":"t1","name":"pytorch","image":"img","serverless":false,"public":true}]}'
  }
  local out
  out="$(rp::cmd_catalog list 2>/dev/null)"
  assert_contains "GET /catalog/templates" "$(<"$cap")"
  assert_contains "t1" "$out"
  assert_contains "pytorch" "$out"
  rp::http() { :; }
  rm -f "$cap"
}

function test_list_json_passes_array() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"templates":[{"id":"t1","name":"pytorch","image":"img","serverless":false,"public":true}]}'
  }
  local out
  out="$(rp::cmd_catalog list --json 2>/dev/null)"
  assert_equals '[{"id":"t1","name":"pytorch","image":"img","serverless":false,"public":true}]' "$out"
  rp::http() { :; }
  rm -f "$cap"
}

function test_unknown_verb_exits_two() {
  rp::http() { :; }
  (rp::cmd_catalog frobnicate >/dev/null 2>&1)
  assert_exit_code 2
}
