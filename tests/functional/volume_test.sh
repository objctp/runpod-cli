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
  source "$RP_ROOT/commands/volume.sh"
  # _volume_create calls rp::warn_unless_s3_dc -> live S3-DC query; stub it so
  # the create tests make no network calls (falls back to the static snapshot).
  _s3_dcs_live() { :; }
  eval "$_opts"
}

function test_should_not_post_when_volume_name_already_exists() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[{"id":"abc","name":"dup","size":10,"dataCenterId":"EU-RO-1"}]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"abc"}'
    fi
  }
  rp::args_parse --name dup --size 10 --dc EU-RO-1
  out="$(_volume_create 2>/dev/null)"
  assert_equals "abc" "$out"
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_post_when_volume_name_is_new() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name fresh --size 10 --dc EU-RO-1
  out="$(_volume_create 2>/dev/null)"
  assert_equals "new1" "$out"
  assert_equals "POSTED" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_show_help_when_help_flag_follows_verb() {
  local out
  out="$(rp::cmd_volume list --help 2>/dev/null)"
  assert_contains "Usage: rp volume" "$out"
}

# main-shell dispatcher call (bashunit skips lines run inside $(...)) so the
# public rp::cmd_volume entry registers coverage.
function test_should_show_help_when_help_verb_given_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_volume help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp volume" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each CRUD verb registers.
function test_should_route_each_volume_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{}'; fi
  }
  rp::cmd_volume list >/dev/null 2>&1
  assert_contains "GET /networkvolumes" "$(<"$cap")"
  rp::cmd_volume get v1 >/dev/null 2>&1
  assert_contains "GET /networkvolumes/v1" "$(<"$cap")"
  rp::cmd_volume create --name n --size 5 --dc EU-RO-1 >/dev/null 2>&1
  assert_contains "POST /networkvolumes" "$(<"$cap")"
  rp::cmd_volume update v1 --size 10 >/dev/null 2>&1
  assert_contains "PATCH /networkvolumes/v1" "$(<"$cap")"
  rp::cmd_volume delete v1 >/dev/null 2>&1
  assert_contains "DELETE /networkvolumes/v1" "$(<"$cap")"
  rm -f "$cap"
}
