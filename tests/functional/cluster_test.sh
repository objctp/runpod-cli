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
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/commands/cluster.sh"
  eval "$_opts"
}

# Capture POST/PATCH body ($3) so create/update request shapes can be asserted.
_capture_http() {
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "${3:-}" >"$_CAP"
      printf '{"id":"cl1"}'
    fi
  }
}

function test_create_posts_cluster_with_compute_shape() {
  local cap
  cap="$(mktemp)"
  _CAP="$cap"
  _capture_http
  rp::args_parse --name tr1 --type TRAINING --gpu "NVIDIA H100 80GB HBM3" --pod-count 4 --gpu-count 8
  _cluster_create >/dev/null 2>&1
  local body
  body="$(<"$cap")"
  assert_equals "tr1" "$(printf '%s' "$body" | jq -r '.name')"
  assert_equals "TRAINING" "$(printf '%s' "$body" | jq -r '.type')"
  assert_equals "NVIDIA H100 80GB HBM3" "$(printf '%s' "$body" | jq -r '.compute.gpuTypeId')"
  assert_equals "8" "$(printf '%s' "$body" | jq -r '.compute.gpuCountPerPod')"
  assert_equals "4" "$(printf '%s' "$body" | jq -r '.compute.podCount')"
  rp::http() { :; }
  rm -f "$cap"
}

function test_create_requires_type_and_gpu() {
  rp::http() { :; }
  rp::args_parse --name n --gpu "NVIDIA L4"
  (_cluster_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse --name n --type TRAINING
  (_cluster_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_rejects_pod_count_below_two() {
  rp::http() { :; }
  rp::args_parse --name n --type TRAINING --gpu "NVIDIA L4" --pod-count 1
  (_cluster_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_rejects_gpu_count_below_one() {
  rp::http() { :; }
  rp::args_parse --name n --type TRAINING --gpu "NVIDIA L4" --gpu-count 0
  (_cluster_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_create_template_id_sets_field() {
  local cap
  cap="$(mktemp)"
  _CAP="$cap"
  _capture_http
  rp::args_parse --name n --type APPLICATION --gpu "NVIDIA L4" --template-id tpl_xyz
  _cluster_create >/dev/null 2>&1
  assert_equals "tpl_xyz" "$(jq -r '.templateId' "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_update_sends_rename_patch() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then printf '[]'; else
      printf '%s' "$3" >"$cap"
      printf '{"id":"cl1"}'
    fi
  }
  rp::cmd_cluster update cl1 --name renamed >/dev/null 2>&1
  assert_equals "renamed" "$(jq -r '.name' "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_should_route_each_cluster_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '{"clusters":[]}'; else printf '{"id":"cl1"}'; fi
  }
  rp::cmd_cluster list >/dev/null 2>&1
  assert_contains "GET /clusters" "$(<"$cap")"
  rp::cmd_cluster get cl1 >/dev/null 2>&1
  assert_contains "GET /clusters/cl1" "$(<"$cap")"
  rp::cmd_cluster create --name n --type TRAINING --gpu "NVIDIA L4" >/dev/null 2>&1
  assert_contains "POST /clusters" "$(<"$cap")"
  rp::cmd_cluster update cl1 --name x >/dev/null 2>&1
  assert_contains "PATCH /clusters/cl1" "$(<"$cap")"
  rp::cmd_cluster delete cl1 >/dev/null 2>&1
  assert_contains "DELETE /clusters/cl1" "$(<"$cap")"
  rp::cmd_cluster pods cl1 >/dev/null 2>&1
  assert_contains "GET /clusters/cl1/pods" "$(<"$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

function test_create_is_idempotent_by_name() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '{"clusters":[{"id":"cl_existing","name":"dup"}]}'
    else
      printf 'POSTED' >>"$cap"
      printf '{"id":"cl_existing"}'
    fi
  }
  local out
  out="$(rp::cmd_cluster create --name dup --type TRAINING --gpu "NVIDIA L4" 2>/dev/null)"
  assert_equals "cl_existing" "$out"
  assert_equals "" "$(cat "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}
