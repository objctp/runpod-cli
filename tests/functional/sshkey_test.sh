#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/commands/ssh-key.sh"
  eval "$_opts"
}

# GET returns the seeded key set; PUT captures its body so add/remove can be
# asserted. Seed is held in a global (not a local of a nested function) so the
# stub survives the helper returning.
# GET returns the seeded key set; PUT captures its body so add/remove can be
# asserted. Seed is held in a global (not a local of a nested function) so the
# stub survives the helper returning.
_stub_sshkey_http() {
  SSHKEY_GET_BODY="$1"
  rp::http() {
    case "$1 $2" in
    "GET /account/ssh-keys") printf '%s' "$SSHKEY_GET_BODY" ;;
    "PUT /account/ssh-keys")
      printf '%s' "$3" >"$_CAP"
      printf '{"keys":[]}'
      ;;
    esac
  }
}

function test_list_tables_keys() {
  rp::http() { printf '{"keys":["ssh-ed25519 AAAABC me@x","ssh-rsa AABB you@y"]}'; }
  local out
  out="$(rp::cmd_ssh-key list 2>/dev/null)"
  assert_contains "ssh-ed25519" "$out"
  assert_contains "ssh-rsa" "$out"
  rp::http() { :; }
}

function test_list_json_returns_array() {
  rp::http() { printf '{"keys":["ssh-ed25519 AAAABC me@x"]}'; }
  local out
  out="$(rp::cmd_ssh-key list --json 2>/dev/null)"
  assert_equals '["ssh-ed25519 AAAABC me@x"]' "$out"
  rp::http() { :; }
}

function test_add_appends_key_and_puts_full_set() {
  local cap keyfile
  cap="$(mktemp)"
  _CAP="$cap"
  _stub_sshkey_http '{"keys":["ssh-ed25519 AAAOLD me@x"]}'
  keyfile="$(mktemp)"
  printf 'ssh-ed25519 AAANEW you@y\n' >"$keyfile"
  rp::cmd_ssh-key add "$keyfile" >/dev/null 2>&1
  # The captured body is the full key set PUT back to /account/ssh-keys.
  assert_equals "2" "$(jq -r '.keys | length' "$cap")"
  assert_equals "ssh-ed25519 AAAOLD me@x" "$(jq -r '.keys[0]' "$cap")"
  assert_equals "ssh-ed25519 AAANEW you@y" "$(jq -r '.keys[1]' "$cap")"
  rp::http() { :; }
  rm -f "$cap" "$keyfile"
}

function test_add_is_idempotent() {
  local cap
  cap="$(mktemp)"
  _CAP="$cap"
  _stub_sshkey_http '{"keys":["ssh-ed25519 AAAOLD me@x"]}'
  # re-adding the same key must not PUT (already registered).
  rp::cmd_ssh-key add <(printf 'ssh-ed25519 AAAOLD me@x\n') >/dev/null 2>&1
  assert_equals "" "$(cat "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_remove_filters_key_and_puts_remainder() {
  local cap
  cap="$(mktemp)"
  _CAP="$cap"
  _stub_sshkey_http '{"keys":["ssh-ed25519 AAAKEEP me@x","ssh-ed25519 AAAOLD you@y"]}'
  rp::cmd_ssh-key remove OLD >/dev/null 2>&1
  assert_equals "1" "$(jq -r '.keys | length' "$cap")"
  assert_equals "ssh-ed25519 AAAKEEP me@x" "$(jq -r '.keys[0]' "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_remove_ambiguous_is_rejected() {
  local cap
  cap="$(mktemp)"
  _CAP="$cap"
  _stub_sshkey_http '{"keys":["ssh-ed25519 AAAONE x","ssh-ed25519 AAATWO x"]}'
  (rp::cmd_ssh-key remove ssh-ed25519 >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(cat "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_unknown_verb_exits_two() {
  rp::http() { :; }
  (rp::cmd_ssh-key frobnicate >/dev/null 2>&1)
  assert_exit_code 2
}
