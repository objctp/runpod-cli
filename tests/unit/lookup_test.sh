#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/lookup.sh"
  eval "$_opts"
}

function rp::http() {
  printf '%s' "$LOOKUP_MOCK"
}

function test_should_return_id_when_name_matches() {
  LOOKUP_MOCK='[{"id":"v1","name":"alpha"},{"id":"v2","name":"beta"}]'
  assert_equals "v2" "$(rp::lookup_id volume beta)"
}

function test_should_return_empty_when_name_missing() {
  LOOKUP_MOCK='[{"id":"v1","name":"alpha"}]'
  assert_equals "" "$(rp::lookup_id volume zeta)"
}

function test_should_return_empty_when_list_is_null() {
  LOOKUP_MOCK='null'
  assert_equals "" "$(rp::lookup_id registry anything)"
}

# main-shell call (bashunit skips lines run inside $(...)) so rp::lookup_id's
# body registers coverage.
function test_should_resolve_id_main_shell() {
  local tmp
  tmp="$(mktemp)"
  LOOKUP_MOCK='[{"id":"v1","name":"alpha"},{"id":"v2","name":"beta"}]'
  rp::lookup_id volume beta >"$tmp"
  assert_equals "v2" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell: drive every resource branch so each path= line registers coverage.
function test_should_resolve_each_resource_main_shell() {
  local tmp
  tmp="$(mktemp)"
  LOOKUP_MOCK='[{"id":"x1","name":"alpha"}]'
  rp::lookup_id pod alpha >"$tmp"
  assert_equals "x1" "$(<"$tmp")"
  rp::lookup_id template alpha >"$tmp"
  assert_equals "x1" "$(<"$tmp")"
  rp::lookup_id registry alpha >"$tmp"
  assert_equals "x1" "$(<"$tmp")"
  rp::lookup_id endpoint alpha >"$tmp"
  assert_equals "x1" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_exit_two_when_resource_unsupported() {
  (rp::lookup_id widget thing >/dev/null 2>&1)
  assert_exit_code 2
}
