#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/validate.sh"
  source "$RP_ROOT/lib/lookup.sh"
  source "$RP_ROOT/commands/pod.sh"
  _s3_dcs_live() { :; }
  eval "$_opts"
}

function test_should_patch_pod_when_resize_fields_given() {
  local meta body
  meta="$(mktemp)"
  body="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$meta"
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --container-disk-gb 100 --volume-gb 200
  _pod_update >/dev/null 2>&1
  assert_equals "PATCH /pods/pod1" "$(cat "$meta")"
  assert_equals "100" "$(jq -r '.containerDiskInGb' "$body")"
  assert_equals "200" "$(jq -r '.volumeInGb' "$body")"
  rp::http() { :; }
  rm -f "$meta" "$body"
}

function test_should_send_env_and_ports_when_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --ports 8080/http,22/tcp --env FOO=bar
  _pod_update >/dev/null 2>&1
  assert_equals "bar" "$(jq -r '.env.FOO' "$body")"
  assert_equals "8080/http" "$(jq -r '.ports[0]' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_pod_update_has_no_fields() {
  rp::http() { :; }
  rp::args_parse pod1
  (_pod_update >/dev/null 2>&1)
  assert_exit_code 2
}

# main-shell dispatcher call so the public rp::cmd_pod entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_pod help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp pod" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing: exercise every public verb through the dispatcher so the
# rp::cmd_pod case branches register coverage (bashunit skips $(...) subshells).
function test_should_route_each_pod_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_pod list >/dev/null 2>&1
  assert_contains "GET /pods" "$(<"$cap")"
  rp::cmd_pod get p1 >/dev/null 2>&1
  assert_contains "GET /pods/p1" "$(<"$cap")"
  rp::cmd_pod create --image img >/dev/null 2>&1
  assert_contains "POST /pods" "$(<"$cap")"
  rp::cmd_pod update p1 --volume-gb 5 >/dev/null 2>&1
  assert_contains "PATCH /pods/p1" "$(<"$cap")"
  rp::cmd_pod start p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/start" "$(<"$cap")"
  rp::cmd_pod stop p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/stop" "$(<"$cap")"
  rp::cmd_pod reset p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/reset" "$(<"$cap")"
  rp::cmd_pod restart p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/restart" "$(<"$cap")"
  rp::cmd_pod delete p1 >/dev/null 2>&1
  assert_contains "DELETE /pods/p1" "$(<"$cap")"
  rm -f "$cap"
}
