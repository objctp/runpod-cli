#!/usr/bin/env bash
# Unit tests for lib/costcenter.sh — the client-side cost-center state layer.
# rp::cc_detect_types is doubled in set_up so state-mutation tests stay
# network-free; its real network behaviour gets its own test with an rp::http
# double keyed by path.
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
  source "$RP_ROOT/lib/costcenter.sh"
  eval "$_opts"
}

function set_up() {
  RP_COST_CENTERS_FILE="$(mktemp -u)"
  CC_CAP="$(mktemp)"
  CC_MOCK='{}'
  # Doubles defined in set_up (after set_up_before_script sourced the libs) so
  # they win over the real rp::http — otherwise tests would hit the live API.
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"$CC_CAP"
    printf '%s' "$CC_MOCK"
  }
}

# Install the cc_detect_types double: maps ids through a "id:type,id:type"
# string (CC_DETECT) so assign/state tests stay network-free. Only tests that
# exercise assignment call this; the detect tests need the real function.
_cc_double_detect() {
  rp::cc_detect_types() {
    local cc_id cc_pair
    for cc_id in "$@"; do
      for cc_pair in ${CC_DETECT:-}; do
        [[ "${cc_pair%%:*}" == "$cc_id" ]] && printf '%s\t%s\n' "$cc_id" "${cc_pair#*:}"
      done
    done
  }
}

function tear_down() {
  rm -f "$RP_COST_CENTERS_FILE" "$CC_CAP"
  rmdir "$(dirname "$RP_COST_CENTERS_FILE")/.cost-centers.lock" 2>/dev/null || true
}

# --- state file seam ---

function test_state_file_resolves_from_config_home_at_use_time() {
  RP_CONFIG_HOME=/tmp/cc-fake-home
  RP_COST_CENTERS_FILE=""
  assert_equals "/tmp/cc-fake-home/cost-centers.json" "$(rp::cc_file)"
}

function test_state_file_honours_explicit_override() {
  RP_COST_CENTERS_FILE=/tmp/cc-explicit.json
  assert_equals "/tmp/cc-explicit.json" "$(rp::cc_file)"
}

function test_state_missing_file_reads_as_empty_skeleton() {
  assert_equals '{"centers":{},"assignments":{}}' "$(rp::cc_state)"
}

function test_state_returns_normalised_content_when_file_exists() {
  printf '%s' '{"centers":{"web":{"note":"n"}},"assignments":{},"extra":1}' >"$RP_COST_CENTERS_FILE"
  local out
  out="$(rp::cc_state)"
  assert_contains '"web"' "$out"
  assert_not_contains '"extra"' "$out"
}

function test_state_normalises_missing_top_level_keys() {
  printf '%s' '{"centers":{"web":{}}}' >"$RP_COST_CENTERS_FILE"
  local out
  out="$(rp::cc_state)"
  assert_equals '{"centers":{"web":{}},"assignments":{}}' "$out"
}

function test_state_exits_one_when_file_is_corrupt() {
  printf '%s' 'not json at all' >"$RP_COST_CENTERS_FILE"
  (rp::cc_state >/dev/null 2>&1)
  assert_exit_code 1
}

function test_state_exits_one_when_file_is_an_array() {
  printf '%s' '[]' >"$RP_COST_CENTERS_FILE"
  (rp::cc_state >/dev/null 2>&1)
  assert_exit_code 1
}

# --- save ---

function test_save_writes_state_and_locks_it_down() {
  rp::cc_save '{"centers":{"web":{}},"assignments":{}}'
  assert_file_exists "$RP_COST_CENTERS_FILE"
  assert_file_contains "$RP_COST_CENTERS_FILE" '"web"'
  local perm
  if stat -f '%Lp' /dev/null >/dev/null 2>&1; then
    perm="$(stat -f '%Lp' "$RP_COST_CENTERS_FILE")"
  else
    perm="$(stat -c '%a' "$RP_COST_CENTERS_FILE")"
  fi
  assert_equals "600" "$perm"
}

function test_save_creates_missing_parent_directory() {
  RP_COST_CENTERS_FILE="$(mktemp -u)/deep/dir/cost-centers.json"
  rp::cc_save '{"centers":{},"assignments":{}}'
  assert_file_exists "$RP_COST_CENTERS_FILE"
}

function test_save_refuses_invalid_state_and_leaves_file_untouched() {
  printf '%s' '{"centers":{},"assignments":{}}' >"$RP_COST_CENTERS_FILE"
  (rp::cc_save 'garbage {' >/dev/null 2>&1)
  assert_exit_code 1
  assert_file_contains "$RP_COST_CENTERS_FILE" '"centers"'
}

# --- state lock (#38) ---

function _cc_lock_dir() {
  printf '%s' "$(dirname "$RP_COST_CENTERS_FILE")/.cost-centers.lock"
}

function test_lock_is_taken_and_released_by_save() {
  rp::cc_save '{"centers":{},"assignments":{}}'
  assert_file_not_exists "$(_cc_lock_dir)"
}

function test_lock_is_taken_and_released_by_the_mutators() {
  rp::cc_create web
  rp::cc_stamp web pod pod_x
  assert_file_not_exists "$(_cc_lock_dir)"
}

function test_lock_fails_when_another_writer_holds_it() {
  rm -rf "$(_cc_lock_dir)" # a stale lock from an earlier run must not interfere
  mkdir "$(_cc_lock_dir)"
  (
    _RP_CC_LOCK_TRIES=3 _RP_CC_LOCK_SLEEP=0.01 rp::cc_lock
  )
  local rc=$?
  rmdir "$(_cc_lock_dir)" 2>/dev/null || true
  assert_equals "1" "$rc"
}

function test_lock_recycles_a_stale_lock_left_by_a_dead_process() {
  rm -rf "$(_cc_lock_dir)" # a stale lock from an earlier run must not interfere
  mkdir "$(_cc_lock_dir)"
  touch -t 202001010000 "$(_cc_lock_dir)" # older than the 2-minute stale age
  rp::cc_lock
  local rc=$?
  rmdir "$(_cc_lock_dir)" # the lock is ours now; release it
  assert_equals "0" "$rc"
}

function test_two_sequential_writes_both_survive() {
  rp::cc_create web
  rp::cc_stamp web pod pod_x
  rp::cc_stamp web serverless ep_y
  local state
  state="$(rp::cc_state)"
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$state"
  assert_contains '"ep_y":{"type":"serverless","center":"web"}' "$state"
}

function test_two_concurrent_stamps_both_survive() {
  rp::cc_create web
  (rp::cc_stamp web pod pod_x >/dev/null 2>&1) &
  (rp::cc_stamp web serverless ep_y >/dev/null 2>&1) &
  wait
  local state
  state="$(rp::cc_state)"
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$state"
  assert_contains '"ep_y":{"type":"serverless","center":"web"}' "$state"
  assert_file_not_exists "$(_cc_lock_dir)"
}

# --- temp registration (#46) ---

function test_save_unregisters_the_temp_after_the_mv() {
  _RP_TEMPS=("/tmp/rp-cc-test-preexisting")
  rp::cc_save '{"centers":{"web":{}},"assignments":{}}'
  # The temp was dropped (renamed into place); unrelated registrations stay.
  assert_equals "/tmp/rp-cc-test-preexisting" "$(printf '%s\n' "${_RP_TEMPS[@]}")"
  _RP_TEMPS=()
}

function test_save_registers_the_temp_when_the_write_fails() {
  mv() { return 1; }
  rp::_cc_save_locked '{"centers":{},"assignments":{}}' >/dev/null 2>&1 || true
  unset -f mv
  # The crashed write's temp stays registered so the EXIT trap removes it.
  assert_equals "1" "${#_RP_TEMPS[@]}"
  assert_file_exists "${_RP_TEMPS[0]}"
  _tmp_cleanup
}

# --- create ---

function test_create_adds_center_with_note() {
  rp::cc_create web "client work"
  local out
  out="$(rp::cc_state)"
  assert_contains '"note":"client work"' "$out"
  assert_contains '"web"' "$out"
}

function test_create_without_note_stores_bare_center() {
  rp::cc_create web
  assert_contains '"web":{}' "$(rp::cc_state)"
}

function test_create_is_idempotent_on_existing_name() {
  rp::cc_create web "first"
  (rp::cc_create web "second" >/dev/null 2>&1)
  assert_successful_code
  assert_contains '"note":"first"' "$(rp::cc_state)"
}

function test_create_exits_two_without_a_name() {
  (rp::cc_create >/dev/null 2>&1)
  assert_exit_code 2
}

# --- require_center ---

function test_require_center_passes_when_present() {
  rp::cc_create web
  rp::cc_require_center web
  assert_successful_code
}

function test_require_center_exits_notfound_when_missing() {
  (rp::cc_require_center ghost >/dev/null 2>&1)
  assert_exit_code 4
}

# --- assign ---

function test_assign_records_typed_entries() {
  _cc_double_detect
  CC_DETECT="pod_x:pod ep_y:serverless"
  rp::cc_create web
  rp::cc_assign web pod_x ep_y
  local out
  out="$(rp::cc_state)"
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$out"
  assert_contains '"ep_y":{"type":"serverless","center":"web"}' "$out"
}

function test_assign_moves_id_from_another_center() {
  _cc_double_detect
  CC_DETECT="pod_x:pod"
  rp::cc_create web
  rp::cc_create infra
  rp::cc_assign infra pod_x
  rp::cc_assign web pod_x
  local out
  out="$(rp::cc_state)"
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$out"
  assert_not_contains '"center":"infra"' "$out"
  assert_contains '"center":"web"' "$out"
}

function test_assign_keeps_the_stored_type_when_already_typed() {
  _cc_double_detect
  CC_DETECT="pod_x:pod"
  rp::cc_create web
  rp::cc_create infra
  rp::cc_assign web pod_x
  # Second assign must not re-probe: the empty CC_DETECT would leave type "".
  CC_DETECT=""
  rp::cc_assign infra pod_x
  assert_contains '"pod_x":{"type":"pod","center":"infra"}' "$(rp::cc_state)"
}

function test_assign_exits_notfound_when_center_missing_and_never_probes() {
  (rp::cc_assign ghost pod_x >/dev/null 2>&1)
  assert_exit_code 4
  assert_equals "" "$(cat "$CC_CAP")"
}

function test_assign_exits_two_without_ids() {
  rp::cc_create web
  (rp::cc_assign web >/dev/null 2>&1)
  assert_exit_code 2
}

function test_assign_rejects_path_metacharacters_in_ids() {
  rp::cc_create web
  (rp::cc_assign web 'pod_x/../../etc' >/dev/null 2>&1)
  assert_exit_code 2
}

# --- stamp (typed assign without probing, used by create verbs) ---

function test_stamp_records_the_type_without_probing() {
  rp::cc_create web
  rp::cc_stamp web pod pod_x
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$(rp::cc_state)"
  assert_equals "" "$(cat "$CC_CAP")"
}

function test_stamp_exits_notfound_when_center_missing() {
  (rp::cc_stamp ghost pod pod_x >/dev/null 2>&1)
  assert_exit_code 4
}

# --- unassign ---

function test_unassign_drops_entries() {
  rp::cc_create web
  rp::cc_stamp web pod pod_x
  rp::cc_unassign pod_x
  assert_not_contains '"pod_x"' "$(rp::cc_state)"
}

function test_unassign_is_idempotent_on_unknown_ids() {
  rp::cc_create web
  rp::cc_unassign never_seen
  assert_successful_code
  assert_equals '{"centers":{"web":{}},"assignments":{}}' "$(rp::cc_state)"
}

function test_unassign_exits_two_without_ids() {
  (rp::cc_unassign >/dev/null 2>&1)
  assert_exit_code 2
}

# --- delete ---

function test_delete_removes_center_and_returns_its_resources_to_untagged() {
  _cc_double_detect
  CC_DETECT="pod_x:pod vol_y:volume"
  rp::cc_create web
  rp::cc_create infra
  rp::cc_assign web pod_x
  rp::cc_assign infra vol_y
  rp::cc_delete web
  local out
  out="$(rp::cc_state)"
  assert_not_contains '"web"' "$out"
  assert_not_contains '"pod_x"' "$out"
  assert_contains '"vol_y"' "$out"
  assert_contains '"infra"' "$out"
}

function test_delete_exits_notfound_when_center_missing() {
  (rp::cc_delete ghost >/dev/null 2>&1)
  assert_exit_code 4
}

# --- read helpers ---

function test_names_prints_centers_in_creation_order() {
  rp::cc_create web
  rp::cc_create infra
  rp::cc_create side
  assert_equals $'web\ninfra\nside' "$(rp::cc_names)"
}

function test_members_prints_ids_of_one_center_only() {
  _cc_double_detect
  CC_DETECT="pod_x:pod ep_y:serverless vol_z:volume"
  rp::cc_create web
  rp::cc_create infra
  rp::cc_assign web pod_x ep_y
  rp::cc_assign infra vol_z
  assert_equals $'pod_x\nep_y' "$(rp::cc_members web)"
}

function test_type_of_prints_the_stored_type() {
  rp::cc_create web
  rp::cc_stamp web cluster cl_1
  assert_equals "cluster" "$(rp::cc_type_of cl_1)"
  assert_equals "" "$(rp::cc_type_of unknown_id)"
}

# --- billing target mapping ---

function test_billing_targets_map_each_type_to_its_endpoint() {
  assert_equals "/billing/pods|podId" "$(rp::cc_billing_targets pod)"
  assert_equals "/billing/serverless|serverlessId" "$(rp::cc_billing_targets serverless)"
  assert_equals "/billing/network-volumes|networkVolumeId" "$(rp::cc_billing_targets volume)"
  assert_equals "/billing/clusters|clusterId" "$(rp::cc_billing_targets cluster)"
}

function test_billing_targets_of_unknown_type_cover_every_product() {
  local out
  out="$(rp::cc_billing_targets '')"
  assert_contains "/billing/pods|podId" "$out"
  assert_contains "/billing/serverless|serverlessId" "$out"
  assert_contains "/billing/network-volumes|networkVolumeId" "$out"
  assert_contains "/billing/clusters|clusterId" "$out"
  assert_equals "4" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
}

# --- type detection (real network seam, rp::http double keyed by path) ---

function test_detect_types_classifies_ids_from_the_resource_lists() {
  rp::http() {
    case "$2" in
    /pods) printf '{"pods":[{"id":"pod_x"},{"id":"pod_y"}]}' ;;
    /serverless) printf '{"endpoints":[{"id":"ep_y"}]}' ;;
    /network-volumes) printf '{"networkVolumes":[{"id":"vol_z"}]}' ;;
    /clusters) printf '{"clusters":[{"id":"cl_1"}]}' ;;
    esac
  }
  local out
  out="$(rp::cc_detect_types pod_x ep_y vol_z cl_1 vanished)"
  assert_contains $'pod_x\tpod' "$out"
  assert_contains $'ep_y\tserverless' "$out"
  assert_contains $'vol_z\tvolume' "$out"
  assert_contains $'cl_1\tcluster' "$out"
  assert_contains $'vanished\t' "$out"
}

function test_detect_types_queries_all_four_lists_once() {
  rp::http() {
    printf '%s\n' "$2" >>"$CC_CAP"
    printf '{}'
  }
  rp::cc_detect_types pod_x >/dev/null
  local paths
  paths="$(sort "$CC_CAP" | tr '\n' ' ')"
  assert_contains "/pods " "$paths"
  assert_contains "/serverless " "$paths"
  assert_contains "/network-volumes " "$paths"
  assert_contains "/clusters " "$paths"
  assert_equals "4" "$(wc -l <"$CC_CAP" | tr -d ' ')"
}
