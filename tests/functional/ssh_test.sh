#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/commands/ssh.sh"
  eval "$_opts"
}

# rp::graphql mock: read-branch returns the existing pubKey; write-branch records
# the written pubKey to the path in RP_SSH_CAPTURE (a file, so it survives the
# command-substitution subshell).
function rp::graphql() {
  if [[ "$1" == *"myself"* ]]; then
    printf '%s' "$RP_SSH_EXISTING"
  else
    [[ -n "${RP_SSH_CAPTURE:-}" ]] && printf '%s' "$2" | jq -r '.input.pubKey' >"$RP_SSH_CAPTURE"
    printf '{"updateUserSettings":{"id":"u"}}'
  fi
}

function test_should_list_each_registered_key() {
  RP_SSH_EXISTING='{"myself":{"pubKey":"ssh-ed25519 AAAA c1\nssh-rsa BBBB c2"}}'
  local out
  out="$(_ssh_list_keys 2>/dev/null)"
  assert_contains "ssh-ed25519" "$out"
  assert_contains "ssh-rsa" "$out"
}

function test_should_append_new_key_and_write_back() {
  RP_SSH_EXISTING='{"myself":{"pubKey":"ssh-ed25519 EXISTING c1"}}'
  local kf capture
  kf="$(mktemp)"
  capture="$(mktemp)"
  printf 'ssh-rsa NEWKEY c2' >"$kf"
  RP_SSH_CAPTURE="$capture"
  rp::args_parse "$kf"
  _ssh_add_key >/dev/null 2>&1
  local written
  written="$(cat "$capture")"
  assert_contains "EXISTING" "$written"
  assert_contains "NEWKEY" "$written"
  rm -f "$kf" "$capture"
}

function test_should_skip_write_when_key_already_present() {
  RP_SSH_EXISTING='{"myself":{"pubKey":"ssh-ed25519 DUP c1"}}'
  local kf capture
  kf="$(mktemp)"
  capture="$(mktemp)"
  printf 'ssh-ed25519 DUP c1' >"$kf"
  RP_SSH_CAPTURE="$capture"
  rp::args_parse "$kf"
  _ssh_add_key >/dev/null 2>&1
  assert_empty "$(cat "$capture")" # no write happened
  rm -f "$kf" "$capture"
}

function test_should_remove_key_by_substring() {
  RP_SSH_EXISTING='{"myself":{"pubKey":"ssh-ed25519 KEEP c1\nssh-rsa GONE c2"}}'
  local capture
  capture="$(mktemp)"
  RP_SSH_CAPTURE="$capture"
  rp::args_parse "GONE"
  _ssh_remove_key >/dev/null 2>&1
  local written
  written="$(cat "$capture")"
  assert_contains "KEEP" "$written"
  assert_not_contains "GONE" "$written"
  rm -f "$capture"
}

function test_should_die_when_remove_target_not_found() {
  RP_SSH_EXISTING='{"myself":{"pubKey":"ssh-ed25519 KEEP c1"}}'
  rp::args_parse "NOPE"
  (_ssh_remove_key >/dev/null 2>&1)
  assert_exit_code 4
}

function test_should_report_no_runtime_for_stopped_pod() {
  rp::http() { printf '{"id":"p","runtime":null}'; }
  rp::args_parse p1
  local out
  out="$(_ssh_info 2>/dev/null)"
  assert_contains "no runtime" "$out"
  rp::http() { :; }
}

# main-shell dispatcher call so the public rp::cmd_ssh entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_ssh help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp ssh" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_ssh_verb() {
  local cap
  cap="$(mktemp)"
  rp::graphql() {
    printf '%s' "$1" >"$cap"
    printf '{"myself":{"pubKey":""}}'
  }
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"id":"p","runtime":null}'
  }
  rp::cmd_ssh list-keys >/dev/null 2>&1
  assert_contains "myself" "$(<"$cap")"
  rp::cmd_ssh info p1 >/dev/null 2>&1
  assert_contains "GET /pods/p1" "$(<"$cap")"
  rm -f "$cap"
}
