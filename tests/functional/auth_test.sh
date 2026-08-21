#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # Set the config home BEFORE sourcing bin/rp so the startup load targets it,
  # then load the command module (rp::main is what normally sources it, but we
  # call rp::cmd_auth directly). rp::_account_name / rp::_load_account are in
  # lib/auth.sh and are always available.
  RP_CONFIG_HOME="$(mktemp -d)"
  export RP_CONFIG_HOME
  source "$RP_ROOT/bin/rp"
  source "$RP_ROOT/commands/auth.sh"
  eval "$_opts"
}

function set_up() {
  mkdir -p "$RP_CONFIG_HOME"
  unset RUNPOD_API_KEY RUNPOD_API_KEY_FILE RUNPOD_S3_ACCESS_KEY RUNPOD_S3_SECRET_KEY RP_ACCOUNT
  RP_ENV_SRC=()
}

function tear_down() {
  rm -rf "$RP_CONFIG_HOME"
}

function test_login_writes_default_account() {
  rp::cmd_auth login --api-key sk-default </dev/null
  assert_file_exists "$RP_CONFIG_HOME/credentials.d/default"
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/default" "RUNPOD_API_KEY=sk-default"
  # active pointer points at default
  assert_file_contains "$RP_CONFIG_HOME/active" "default"
}

function test_login_named_account() {
  rp::cmd_auth login --name work --api-key sk-work </dev/null
  assert_file_exists "$RP_CONFIG_HOME/credentials.d/work"
  assert_file_contains "$RP_CONFIG_HOME/active" "work"
}

function test_login_file_is_locked_down() {
  rp::cmd_auth login --api-key sk-default </dev/null
  assert_file_permissions "600" "$RP_CONFIG_HOME/credentials.d/default"
  assert_file_permissions "700" "$RP_CONFIG_HOME"
  assert_file_permissions "700" "$RP_CONFIG_HOME/credentials.d"
}

function test_login_stores_key_unquoted() {
  rp::cmd_auth login --api-key sk-default </dev/null
  assert_file_not_contains "$RP_CONFIG_HOME/credentials.d/default" '"'
}

function test_login_preserves_other_lines_in_account() {
  mkdir -p "$RP_CONFIG_HOME/credentials.d"
  printf 'RP_FOO=bar\nRUNPOD_API_KEY=stale\n' >"$RP_CONFIG_HOME/credentials.d/work"
  rp::cmd_auth login --name work --api-key sk-replaced </dev/null
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/work" "RP_FOO=bar"
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/work" "RUNPOD_API_KEY=sk-replaced"
  assert_file_not_contains "$RP_CONFIG_HOME/credentials.d/work" "RUNPOD_API_KEY=stale"
}

function test_login_reads_key_from_stdin_when_piped() {
  printf 'sk-from-stdin\n' | rp::cmd_auth login
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/default" "RUNPOD_API_KEY=sk-from-stdin"
}

function test_status_reports_active_account_and_source() {
  rp::cmd_auth login --api-key sk-status123 --s3-access-key AKIAx --s3-secret-key SKy </dev/null
  local out
  out="$(rp::cmd_auth status 2>/dev/null)"
  assert_contains "ACTIVE ACCOUNT  default" "$out"
  assert_contains "configured" "$out"
  assert_contains "sk-…s123" "$out"
  assert_contains "account file ($RP_CONFIG_HOME/credentials.d/default)" "$out"
  assert_contains "S3 KEYS" "$out"
}

function test_list_marks_active() {
  rp::cmd_auth login --name work --api-key sk-workabcd </dev/null
  rp::cmd_auth login --name personal --api-key sk-persabcd </dev/null
  local out
  out="$(rp::cmd_auth list 2>&1 >/dev/null)"
  assert_contains "personal (active)" "$out"
  assert_contains "work" "$out"
}

function test_switch_changes_active() {
  rp::cmd_auth login --name work --api-key sk-work </dev/null
  rp::cmd_auth login --name personal --api-key sk-personal </dev/null
  rp::cmd_auth switch work
  assert_file_contains "$RP_CONFIG_HOME/active" "work"
  local out
  out="$(rp::cmd_auth status 2>/dev/null)"
  assert_contains "ACTIVE ACCOUNT  work" "$out"
}

function test_use_alias_switches() {
  rp::cmd_auth login --name work --api-key sk-work </dev/null
  rp::cmd_auth login --name personal --api-key sk-personal </dev/null
  rp::cmd_auth use work
  assert_file_contains "$RP_CONFIG_HOME/active" "work"
}

function test_account_flag_selects_non_active() {
  rp::cmd_auth login --name work --api-key sk-workabcd </dev/null
  rp::cmd_auth login --name personal --api-key sk-persabcd </dev/null
  # active is personal; --account work should report work's token
  local out
  out="$(rp::cmd_auth status --account work 2>/dev/null)"
  assert_contains "sk-…abcd" "$out"
  assert_contains "ACTIVE ACCOUNT  work" "$out"
}

function test_logout_removes_account_and_switches_active() {
  rp::cmd_auth login --name work --api-key sk-work </dev/null
  rp::cmd_auth login --name personal --api-key sk-personal </dev/null
  rp::cmd_auth logout --name personal
  assert_file_not_exists "$RP_CONFIG_HOME/credentials.d/personal"
  # active should have switched to the remaining account
  assert_file_contains "$RP_CONFIG_HOME/active" "work"
}

function test_logout_last_account_clears_active() {
  rp::cmd_auth login --name only --api-key sk-only </dev/null
  rp::cmd_auth logout --name only
  assert_file_not_exists "$RP_CONFIG_HOME/credentials.d/only"
  assert_file_not_exists "$RP_CONFIG_HOME/active"
}

function test_explicit_env_var_wins_over_accounts() {
  rp::cmd_auth login --name work --api-key sk-work </dev/null
  RUNPOD_API_KEY=sk-explicit rp::cmd_auth status 2>/dev/null
  local out
  out="$(RUNPOD_API_KEY=sk-explicit rp::cmd_auth status 2>/dev/null)"
  assert_contains "sk-…icit" "$out"
  assert_contains "environment (exported)" "$out"
}

function test_unknown_verb_usage() {
  local out
  out="$(rp::cmd_auth bogus 2>&1)"
  assert_contains "unknown auth verb" "$out"
}

function test_login_from_runpodctl_imports_key() {
  local rpc
  rpc="$(mktemp -u).toml"
  printf 'apiKey = "rpa_fromrpc"\n' >"$rpc"
  RUNPODCTL_CONFIG="$rpc" rp::cmd_auth login --from-runpodctl </dev/null
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/default" "RUNPOD_API_KEY=rpa_fromrpc"
  rm -f "$rpc"
}

function test_login_from_runpodctl_explicit_key_wins() {
  local rpc
  rpc="$(mktemp -u).toml"
  printf 'apiKey = "rpa_fromrpc"\n' >"$rpc"
  RUNPODCTL_CONFIG="$rpc" rp::cmd_auth login --api-key sk-explicit --from-runpodctl </dev/null
  assert_file_contains "$RP_CONFIG_HOME/credentials.d/default" "RUNPOD_API_KEY=sk-explicit"
  rm -f "$rpc"
}

function test_login_from_runpodctl_missing_key_dies() {
  local rpc out rc=0
  rpc="$(mktemp -u).toml"
  printf 'other = true\n' >"$rpc"
  # Capture via a subshell so rp::die's exit doesn't abort the test.
  out="$(RUNPODCTL_CONFIG="$rpc" rp::cmd_auth login --from-runpodctl </dev/null 2>/dev/null)"
  rc=$?
  assert_equals 1 "$rc"
  assert_file_not_exists "$RP_CONFIG_HOME/credentials.d/default"
  rm -f "$rpc"
}
