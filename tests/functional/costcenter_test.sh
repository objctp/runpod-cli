#!/usr/bin/env bash
# Functional tests for rp cost-center — verb dispatch, local state effects and
# the spend roll-up against the per-resource billing endpoints. rp::http is a
# path-keyed double: the four resource lists classify ids, and each billing
# endpoint returns a fixed window total.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/billing.sh"
  source "$RP_ROOT/lib/costcenter.sh"
  source "$RP_ROOT/commands/cost-center.sh"
  eval "$_opts"
}

function set_up() {
  RP_COST_CENTERS_FILE="$(mktemp -u)"
  CC_CALLS="$(mktemp)"
  CC_OUT="$(mktemp)"
  # Path-keyed transport double: every call is logged, the resource lists know
  # pod_x/pod_y (pods), ep_y (serverless), vol_z (volumes), cl_1 (clusters),
  # and each billing product returns its own fixed window total.
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"$CC_CALLS"
    case "$2" in
    /pods) printf '{"pods":[{"id":"pod_x"},{"id":"pod_y"}]}' ;;
    /serverless) printf '{"endpoints":[{"id":"ep_y"}]}' ;;
    /network-volumes) printf '{"networkVolumes":[{"id":"vol_z"}]}' ;;
    /clusters) printf '{"clusters":[{"id":"cl_1"}]}' ;;
    /billing/pods*) printf '{"records":[],"metadata":{"totals":{"totalAmount":10}}}' ;;
    /billing/serverless*) printf '{"records":[],"metadata":{"totals":{"totalAmount":2.5}}}' ;;
    /billing/network-volumes*) printf '{"records":[],"metadata":{"totals":{"totalAmount":0}}}' ;;
    /billing/clusters*) printf '{"records":[],"metadata":{"totals":{"totalAmount":7}}}' ;;
    *) printf '{}' ;;
    esac
  }
}

function tear_down() {
  rm -f "$RP_COST_CENTERS_FILE" "$CC_CALLS" "$CC_OUT"
}

function _seed() {
  rp::cc_create web
  rp::cc_stamp web pod pod_x
  rp::cc_stamp web serverless ep_y
}

function test_create_verb_writes_the_center_and_note() {
  rp::cmd_cost_center create web --note "client work" >/dev/null 2>&1
  assert_file_contains "$RP_COST_CENTERS_FILE" '"note":"client work"'
}

function test_list_renders_name_note_and_resource_counts() {
  _seed
  rp::cmd_cost_center list >"$CC_OUT" 2>/dev/null
  local out
  out="$(<"$CC_OUT")"
  assert_contains "web" "$out"
  assert_contains "2" "$out"
}

function test_list_json_prints_the_rows_array() {
  _seed
  rp::cmd_cost_center list --json >"$CC_OUT" 2>/dev/null
  local out
  out="$(<"$CC_OUT")"
  assert_contains '"name":"web"' "$out"
  assert_contains '"resources":2' "$out"
}

function test_assign_verb_probes_the_lists_and_records_types() {
  rp::cmd_cost_center create web >/dev/null 2>&1
  rp::cmd_cost_center assign web pod_x ep_y vol_z cl_1 >/dev/null 2>&1
  local state
  state="$(rp::cc_state)"
  assert_contains '"pod_x":{"type":"pod","center":"web"}' "$state"
  assert_contains '"ep_y":{"type":"serverless","center":"web"}' "$state"
  assert_contains '"vol_z":{"type":"volume","center":"web"}' "$state"
  assert_contains '"cl_1":{"type":"cluster","center":"web"}' "$state"
}

function test_assign_verb_exits_notfound_when_center_missing() {
  (rp::cmd_cost_center assign ghost pod_x >/dev/null 2>&1)
  assert_exit_code 4
}

function test_unassign_verb_drops_the_entry() {
  _seed
  rp::cmd_cost_center unassign pod_x >/dev/null 2>&1
  assert_not_contains '"pod_x"' "$(rp::cc_state)"
}

function test_unassign_verb_exits_two_without_ids() {
  (rp::cmd_cost_center unassign >/dev/null 2>&1)
  assert_exit_code 2
}

function test_delete_verb_untags_the_members() {
  _seed
  rp::cmd_cost_center delete web >/dev/null 2>&1
  local state
  state="$(rp::cc_state)"
  assert_not_contains '"web"' "$state"
  assert_not_contains '"pod_x"' "$state"
}

function test_delete_verb_exits_notfound_when_center_missing() {
  (rp::cmd_cost_center delete ghost >/dev/null 2>&1)
  assert_exit_code 4
}

# --- spend ---

function test_spend_sums_each_member_over_the_window() {
  _seed
  rp::cmd_cost_center spend web >"$CC_OUT" 2>/dev/null
  local out
  out="$(<"$CC_OUT")"
  assert_contains "web" "$out"
  # pod (10) + serverless (2.5) = 12.5, in both the row and the TOTAL row.
  assert_contains "12.5" "$out"
  assert_contains "TOTAL" "$out"
}

function test_spend_bills_each_typed_resource_against_its_own_product_only() {
  _seed
  rp::cmd_cost_center spend web >/dev/null 2>&1
  local billing_calls
  billing_calls="$(grep -c 'GET /billing/' "$CC_CALLS")"
  assert_equals "2" "$billing_calls"
  assert_contains "GET /billing/pods?podId=pod_x" "$(cat "$CC_CALLS")"
  assert_contains "GET /billing/serverless?serverlessId=ep_y" "$(cat "$CC_CALLS")"
}

function test_spend_forwards_the_window_flags_to_billing() {
  _seed
  rp::cmd_cost_center spend web --last-n 7 >/dev/null 2>&1
  assert_contains "GET /billing/pods?podId=pod_x&lastN=7" "$(cat "$CC_CALLS")"
}

function test_spend_rejects_an_invalid_window_before_any_call() {
  _seed
  : >"$CC_CALLS"
  (rp::cmd_cost_center spend web --bucket-size fortnight >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(cat "$CC_CALLS")"
}

function test_spend_of_an_untyped_resource_bills_every_product() {
  rp::cc_create web
  rp::cc_stamp web "" mystery_id
  rp::cmd_cost_center spend web >/dev/null 2>&1
  local calls
  calls="$(cat "$CC_CALLS")"
  assert_contains "GET /billing/pods?podId=mystery_id" "$calls"
  assert_contains "GET /billing/serverless?serverlessId=mystery_id" "$calls"
  assert_contains "GET /billing/network-volumes?networkVolumeId=mystery_id" "$calls"
  assert_contains "GET /billing/clusters?clusterId=mystery_id" "$calls"
}

function test_spend_without_a_name_rolls_up_every_center_plus_uncategorized() {
  _seed
  # ep_y is tagged; pod_y, vol_z and cl_1 stay unassigned (10 + 0 + 7).
  rp::cmd_cost_center spend >"$CC_OUT" 2>/dev/null
  local out
  out="$(<"$CC_OUT")"
  assert_contains "web" "$out"
  assert_contains "Uncategorized" "$out"
  # web 12.5 + Uncategorized 17 = 29.5 total.
  assert_contains "29.5" "$out"
}

function test_spend_json_prints_the_full_breakdown() {
  _seed
  rp::cmd_cost_center spend web --json >"$CC_OUT" 2>/dev/null
  local out
  out="$(<"$CC_OUT")"
  assert_contains '"name":"web"' "$out"
  assert_contains '"id":"pod_x"' "$out"
  assert_contains '"total":12.5' "$out"
}

function test_spend_exits_notfound_for_an_unknown_center() {
  (rp::cmd_cost_center spend ghost >/dev/null 2>&1)
  assert_exit_code 4
}

# --- dispatch ---

function test_help_verb_prints_usage() {
  rp::cmd_cost_center help >"$CC_OUT" 2>/dev/null
  assert_contains "Usage: rp cost-center" "$(<"$CC_OUT")"
}

function test_unknown_verb_exits_two() {
  (rp::cmd_cost_center __bogus__ >/dev/null 2>&1)
  assert_exit_code 2
}
