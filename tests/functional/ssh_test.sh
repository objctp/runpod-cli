#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/commands/ssh.sh"
  eval "$_opts"
}

# bashunit runs set_up after set_up_before_script (which sources lib/http.sh and
# defines the real rp::http), so the mock is defined here to win. The v2 account
# key route returns RP_SSH_EXISTING (a {keys:[…]} object); the PUT writes the new
# key set to RP_SSH_CAPTURE (a file, so it survives the command-substitution
# subshell). Everything else (GET /pods/p1) returns a stopped-pod record.
function set_up() {
  function rp::http() {
    local method="$1" path="$2" body="$3"
    case "$method $path" in
    "GET /account/ssh-keys") printf '%s' "$RP_SSH_EXISTING" ;;
    "PUT /account/ssh-keys")
      [[ -n "${RP_SSH_CAPTURE:-}" ]] && printf '%s' "$body" | jq -r '.keys | join("\n")' >"$RP_SSH_CAPTURE"
      printf '{"keys":[]}'
      ;;
    *) printf '{"id":"p","runtime":null}' ;;
    esac
  }
}

function test_should_list_each_registered_key() {
  RP_SSH_EXISTING='{"keys":["ssh-ed25519 AAAA c1","ssh-rsa BBBB c2"]}'
  local out
  out="$(_ssh_list_keys 2>/dev/null)"
  assert_contains "ssh-ed25519" "$out"
  assert_contains "ssh-rsa" "$out"
}

function test_should_append_new_key_and_write_back() {
  RP_SSH_EXISTING='{"keys":["ssh-ed25519 EXISTING c1"]}'
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
  RP_SSH_EXISTING='{"keys":["ssh-ed25519 DUP c1"]}'
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
  RP_SSH_EXISTING='{"keys":["ssh-ed25519 KEEP c1","ssh-rsa GONE c2"]}'
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
  RP_SSH_EXISTING='{"keys":["ssh-ed25519 KEEP c1"]}'
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
  rp::http() { printf '%s %s\n' "$1" "$2" >"$cap"; }
  RP_SSH_EXISTING='{"keys":[]}'
  rp::cmd_ssh list-keys >/dev/null 2>&1
  assert_contains "GET /account/ssh-keys" "$(<"$cap")"
  rp::cmd_ssh info p1 >/dev/null 2>&1
  assert_contains "GET /pods/p1" "$(<"$cap")"
  rm -f "$cap"
}
