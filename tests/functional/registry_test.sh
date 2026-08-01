#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/commands/registry.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  REGISTRY_BODY='[{"id":"reg1","name":"dockerhub"}]'
  # Default double returns the configured body; create/delete tests override it
  # to inspect method, path, and request body. Defined in set_up so it wins over
  # the real rp::http.
  rp::http() { printf '%s' "$REGISTRY_BODY"; }
}

function tear_down() {
  rm -f "$OUT"
}

function test_should_return_raw_array_when_list_json() {
  rp::cmd_registry list --json >"$OUT"
  assert_equals "$REGISTRY_BODY" "$(<"$OUT")"
}

function test_should_render_table_when_list_no_json() {
  rp::cmd_registry list >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "dockerhub" "$rendered"
  assert_contains "reg1" "$rendered"
}

function test_should_exit_two_when_get_has_no_id() {
  (rp::cmd_registry get >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_return_body_when_get_given_id() {
  REGISTRY_BODY='{"id":"reg1","name":"dockerhub"}'
  rp::cmd_registry get reg1 >"$OUT"
  assert_contains "dockerhub" "$(<"$OUT")"
}

function test_should_exit_two_when_create_missing_required_fields() {
  rp::args_parse --username u
  (_registry_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_post_body_and_print_id_when_create_given_all() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"reg9"}'
  }
  rp::args_parse --name n --username u --password p
  local out
  out="$(_registry_create 2>/dev/null)"
  assert_equals "reg9" "$out"
  local rendered
  rendered="$(<"$cap")"
  assert_contains '"name":"n"' "$rendered"
  assert_contains '"username":"u"' "$rendered"
  assert_contains '"password":"p"' "$rendered"
  rm -f "$cap"
}

function test_should_exit_two_when_delete_has_no_id() {
  (rp::cmd_registry delete >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_call_delete_endpoint_when_delete_given_id() {
  local marker
  marker="$(mktemp)"
  rp::http() { printf '%s %s' "$1" "$2" >"$marker"; }
  rp::cmd_registry delete reg1 >/dev/null 2>&1
  assert_equals "DELETE /registries/reg1" "$(<"$marker")"
  rm -f "$marker"
}

function test_should_show_help_when_help_verb_given() {
  rp::cmd_registry help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp registry" "$(<"$OUT")"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_registry_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{"id":"reg1"}'; fi
  }
  rp::cmd_registry list >/dev/null 2>&1
  assert_contains "GET /registries" "$(<"$cap")"
  rp::cmd_registry get reg1 >/dev/null 2>&1
  assert_contains "GET /registries/reg1" "$(<"$cap")"
  rp::cmd_registry create --name n --username u --password p >/dev/null 2>&1
  assert_contains "POST /registries" "$(<"$cap")"
  rp::cmd_registry delete reg1 >/dev/null 2>&1
  assert_contains "DELETE /registries/reg1" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_exit_two_when_registry_verb_unknown() {
  (rp::cmd_registry __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}

# --- delegations ---

function test_delegations_list_json_emits_array() {
  local body='{"delegations":[{"id":"deleg_1","name":"d1","repository":"r/t","tag":"latest","awsRegion":"us-east-2","awsUser":"123","delegatorUserId":"u","createdAt":"2026-03-13T20:00:00Z"}]}'
  rp::http() { printf '%s' "$body"; }
  rp::cmd_registry delegations list --json >"$OUT"
  assert_equals '[{"id":"deleg_1","name":"d1","repository":"r/t","tag":"latest","awsRegion":"us-east-2","awsUser":"123","delegatorUserId":"u","createdAt":"2026-03-13T20:00:00Z"}]' "$(<"$OUT")"
}

function test_delegations_list_renders_table() {
  local body='{"delegations":[{"id":"deleg_1","name":"d1","repository":"r/t","tag":"latest","awsRegion":"us-east-2","awsUser":"123","delegatorUserId":"u","createdAt":"2026-03-13T20:00:00Z"}]}'
  rp::http() { printf '%s' "$body"; }
  rp::cmd_registry delegations list >"$OUT" 2>/dev/null
  local rendered
  rendered="$(<"$OUT")"
  assert_contains "ID	NAME	REPOSITORY	TAG	REGION	CREATED" "$rendered"
  assert_contains "deleg_1	d1	r/t	latest	us-east-2	2026-03-13T20:00:00Z" "$rendered"
}

function test_delegations_create_sends_resource_and_name() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"deleg_9"}'
  }
  rp::args_parse --resource "arn:aws:ecr:us-east-2:1:repo/r" --name d1
  local out
  out="$(_registry_delegations_create 2>/dev/null)"
  assert_equals "deleg_9" "$out"
  assert_contains '"resource":"arn:aws:ecr:us-east-2:1:repo/r"' "$(<"$cap")"
  assert_contains '"name":"d1"' "$(<"$cap")"
  rm -f "$cap"
}

function test_delegations_create_omits_name_when_absent() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"deleg_9"}'
  }
  rp::args_parse --resource "arn:aws:ecr:us-east-2:1:repo/r"
  _registry_delegations_create >/dev/null 2>&1
  assert_equals "false" "$(jq -c 'has("name")' <"$cap")"
  assert_contains '"resource":"arn:aws:ecr:us-east-2:1:repo/r"' "$(<"$cap")"
  rm -f "$cap"
}

function test_delegations_create_exits_two_without_resource() {
  (rp::cmd_registry delegations create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_delegations_revoke_routes_correctly() {
  local marker
  marker="$(mktemp)"
  rp::http() { printf '%s %s' "$1" "$2" >"$marker"; }
  rp::cmd_registry delegations revoke deleg_1 >/dev/null 2>&1
  assert_equals "DELETE /registries/delegations/deleg_1" "$(<"$marker")"
  rm -f "$marker"
}

function test_delegations_revoke_exits_two_without_id() {
  (rp::cmd_registry delegations revoke >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_route_each_delegations_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '{"delegations":[]}'; else printf '{"id":"d1"}'; fi
  }
  rp::cmd_registry delegations list >/dev/null 2>&1
  assert_contains "GET /registries/delegations" "$(<"$cap")"
  rp::cmd_registry delegations create --resource arn:aws:ecr:us-east-2:1:repo/r >/dev/null 2>&1
  assert_contains "POST /registries/delegations" "$(<"$cap")"
  rp::cmd_registry delegations revoke d1 >/dev/null 2>&1
  assert_contains "DELETE /registries/delegations/d1" "$(<"$cap")"
  rm -f "$cap"
}

function test_delegations_help_mentions_usage() {
  rp::cmd_registry delegations help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp registry delegations" "$(<"$OUT")"
}

function test_help_mentions_delegations() {
  rp::cmd_registry help >"$OUT" 2>/dev/null
  assert_contains "delegations" "$(<"$OUT")"
}
