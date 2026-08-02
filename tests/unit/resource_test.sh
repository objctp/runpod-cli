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
  eval "$_opts"
}

function rp::http() {
  printf '%s %s\n' "$1" "$2" >>"${RES_CAP:-/dev/null}"
  printf '%s' "$RES_MOCK"
}

function set_up() {
  RES_CAP="$(mktemp)"
  RES_MOCK='[]'
}

function tear_down() {
  rm -f "$RES_CAP"
}

# --- descriptor ---

# Main-shell: drive every resource branch so each descriptor arm registers.
function test_should_map_each_resource_to_its_path_and_key() {
  _resource_meta pod
  assert_equals "/pods" "$RP_RES_PATH"
  assert_equals "pods" "$RP_RES_KEY"
  _resource_meta volume
  assert_equals "/network-volumes" "$RP_RES_PATH"
  assert_equals "networkVolumes" "$RP_RES_KEY"
  _resource_meta serverless
  assert_equals "/serverless" "$RP_RES_PATH"
  assert_equals "endpoints" "$RP_RES_KEY"
  _resource_meta template
  assert_equals "/templates" "$RP_RES_PATH"
  assert_equals "templates" "$RP_RES_KEY"
  _resource_meta registry
  assert_equals "/registries" "$RP_RES_PATH"
  assert_equals "registry auth" "$RP_RES_LABEL"
}

function test_should_exit_two_when_resource_unknown() {
  (_resource_meta widget >/dev/null 2>&1)
  assert_exit_code 2
}

# --- resource_id (absorbed from lookup) ---

function test_should_return_id_when_name_matches() {
  RES_MOCK='[{"id":"v1","name":"alpha"},{"id":"v2","name":"beta"}]'
  assert_equals "v2" "$(rp::resource_id volume beta)"
}

function test_should_return_empty_when_name_missing() {
  RES_MOCK='[{"id":"v1","name":"alpha"}]'
  assert_equals "" "$(rp::resource_id volume zeta)"
}

function test_should_return_empty_when_list_is_null() {
  RES_MOCK='null'
  assert_equals "" "$(rp::resource_id registry anything)"
}

# main-shell call (bashunit skips lines run inside $(...)) so rp::resource_id's
# body registers coverage.
function test_should_resolve_id_main_shell() {
  local tmp
  tmp="$(mktemp)"
  RES_MOCK='[{"id":"v1","name":"alpha"},{"id":"v2","name":"beta"}]'
  rp::resource_id volume beta >"$tmp"
  assert_equals "v2" "$(<"$tmp")"
  rm -f "$tmp"
}

# v2 list bodies arrive wrapped in a single named array key.
function test_should_resolve_id_when_list_is_wrapped() {
  RES_MOCK='{"networkVolumes":[{"id":"v1","name":"alpha"},{"id":"v2","name":"beta"}]}'
  assert_equals "v2" "$(rp::resource_id volume beta)"
  RES_MOCK='{"registries":[{"id":"r1","name":"alpha"}]}'
  assert_equals "r1" "$(rp::resource_id registry alpha)"
  RES_MOCK='{"endpoints":[{"id":"e1","name":"alpha"}]}'
  assert_equals "e1" "$(rp::resource_id serverless alpha)"
}

function test_should_exit_two_when_id_resource_unsupported() {
  (rp::resource_id widget thing >/dev/null 2>&1)
  assert_exit_code 2
}

# --- volume datacenter resolution (absorbed from the 6-site idiom) ---

function test_should_resolve_volume_name_to_id_and_dc() {
  RES_MOCK='{"networkVolumes":[{"id":"v1","name":"models","dataCenter":"EU-RO-1"}],"dataCenter":"EU-RO-1"}'
  rp::volume_dc models
  assert_equals "v1" "$RP_VOLUME_ID"
  assert_equals "EU-RO-1" "$RP_VOLUME_DC"
}

function test_should_exit_notfound_when_volume_name_missing() {
  RES_MOCK='{"networkVolumes":[]}'
  (rp::volume_dc zeta >/dev/null 2>&1)
  assert_exit_code 4
}

function test_should_die_when_volume_has_no_datacenter() {
  RES_MOCK='{"networkVolumes":[{"id":"v1","name":"models"}]}'
  (rp::volume_dc models >/dev/null 2>&1)
  assert_general_error "$?"
}

function test_should_resolve_volume_id_to_dc() {
  RES_MOCK='{"dataCenter":"EU-RO-2"}'
  rp::volume_dc_id v7
  assert_equals "v7" "$RP_VOLUME_ID"
  assert_equals "EU-RO-2" "$RP_VOLUME_DC"
}

function test_should_die_when_volume_id_has_no_datacenter() {
  RES_MOCK='{}'
  (rp::volume_dc_id v9 >/dev/null 2>&1)
  assert_general_error "$?"
}

# --- resource_list ---

function test_should_return_raw_array_when_list_json() {
  local tmp
  tmp="$(mktemp)"
  RES_MOCK='{"pods":[{"id":"p1","name":"alpha"}]}'
  rp::args_parse --json
  rp::resource_list pod id name >"$tmp"
  assert_equals '[{"id":"p1","name":"alpha"}]' "$(<"$tmp")"
  assert_contains "GET /pods" "$(<"$RES_CAP")"
  rm -f "$tmp"
}

function test_should_render_table_when_list_no_json() {
  local tmp
  tmp="$(mktemp)"
  RES_MOCK='{"templates":[{"id":"t1","name":"tpl","image":"img"}]}'
  rp::args_parse
  rp::resource_list template id name image >"$tmp" 2>/dev/null
  local rendered
  rendered="$(<"$tmp")"
  assert_contains "t1" "$rendered"
  assert_contains "tpl" "$rendered"
  rm -f "$tmp"
}

# --- resource_get ---

function test_should_exit_two_when_get_has_no_id() {
  rp::args_parse
  (rp::resource_get volume >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_fetch_record_when_get_given_id() {
  local tmp
  tmp="$(mktemp)"
  RES_MOCK='{"id":"nv1","name":"models"}'
  rp::args_parse nv1
  rp::resource_get volume >"$tmp"
  assert_contains "models" "$(<"$tmp")"
  assert_contains "GET /network-volumes/nv1" "$(<"$RES_CAP")"
  rm -f "$tmp"
}

# --- resource_create ---

function test_should_post_and_print_id_when_create_given_body() {
  local tmp msg
  tmp="$(mktemp)"
  msg="$(mktemp)"
  RES_MOCK='{"id":"p9"}'
  rp::args_parse
  rp::resource_create pod "" '{"image":"img"}' >"$tmp" 2>"$msg"
  assert_equals "p9" "$(<"$tmp")"
  assert_contains "POST /pods" "$(<"$RES_CAP")"
  assert_contains "created pod: p9" "$(<"$msg")"
  rm -f "$tmp" "$msg"
}

function test_should_return_existing_id_when_name_already_taken() {
  local tmp msg
  tmp="$(mktemp)"
  msg="$(mktemp)"
  RES_MOCK='{"networkVolumes":[{"id":"v1","name":"models"}]}'
  rp::args_parse
  rp::resource_create volume models '{"name":"models"}' >"$tmp" 2>"$msg"
  assert_equals "v1" "$(<"$tmp")"
  assert_contains "volume 'models' exists: v1" "$(<"$msg")"
  local calls
  calls="$(<"$RES_CAP")"
  assert_not_contains "POST" "$calls"
  rm -f "$tmp" "$msg"
}

function test_should_post_when_force_given_despite_existing_name() {
  local tmp
  tmp="$(mktemp)"
  RES_MOCK='{"id":"v2"}'
  rp::args_parse --force
  rp::resource_create volume models '{"name":"models"}' >"$tmp" 2>/dev/null
  assert_equals "v2" "$(<"$tmp")"
  assert_contains "POST /network-volumes" "$(<"$RES_CAP")"
  rm -f "$tmp"
}

function test_should_append_detail_and_name_to_create_message() {
  local msg
  msg="$(mktemp)"
  RES_MOCK='{"id":"v3"}'
  rp::args_parse --force
  rp::resource_create volume models '{}' "EU-RO-1, 20GB" >/dev/null 2>"$msg"
  assert_contains "created volume 'models': v3 (EU-RO-1, 20GB)" "$(<"$msg")"
  rm -f "$msg"
}

function test_should_die_when_create_response_has_no_id() {
  RES_MOCK='{}'
  rp::args_parse
  (rp::resource_create pod "" '{}' >/dev/null 2>&1)
  assert_general_error "$?"
}

# --- resource_existing ---

function test_should_print_id_and_confirm_when_existing_name_matches() {
  local tmp msg
  tmp="$(mktemp)"
  msg="$(mktemp)"
  RES_MOCK='{"endpoints":[{"id":"e1","name":"glm"}]}'
  rp::args_parse
  rp::resource_existing serverless glm >"$tmp" 2>"$msg"
  assert_equals "e1" "$(<"$tmp")"
  assert_contains "serverless 'glm' exists: e1" "$(<"$msg")"
  assert_not_contains "POST" "$(<"$RES_CAP")"
  rm -f "$tmp" "$msg"
}

function test_should_return_one_when_existing_name_absent_forced_or_empty() {
  RES_MOCK='{"networkVolumes":[{"id":"v1","name":"models"}]}'
  rp::args_parse
  (rp::resource_existing volume zeta >/dev/null 2>&1)
  assert_general_error "$?"
  rp::args_parse --force
  (rp::resource_existing volume models >/dev/null 2>&1)
  assert_general_error "$?"
  rp::args_parse
  (rp::resource_existing volume "" >/dev/null 2>&1)
  assert_general_error "$?"
}

# --- resource_delete ---

function test_should_exit_two_when_delete_has_no_id() {
  rp::args_parse
  (rp::resource_delete pod >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_delete_and_use_label_when_delete_given_id() {
  local msg
  msg="$(mktemp)"
  RES_MOCK='{}'
  rp::args_parse reg1
  rp::resource_delete registry 2>"$msg"
  assert_contains "DELETE /registries/reg1" "$(<"$RES_CAP")"
  assert_contains "deleted registry auth reg1" "$(<"$msg")"
  rm -f "$msg"
}
