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
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/commands/pod.sh"
  _s3_dcs_live() { :; }
  eval "$_opts"
}

function test_should_patch_pod_when_resize_fields_given() {
  local meta body
  meta="$(mktemp)"
  body="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$meta"
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --container-disk-gb 100 --volume-gb 200
  _pod_update >/dev/null 2>&1
  assert_equals "PATCH /pods/pod1" "$(cat "$meta")"
  assert_equals "100" "$(jq -r '.disk' "$body")"
  assert_equals "200" "$(jq -r '.mounts.persistent.size' "$body")"
  rp::http() { :; }
  rm -f "$meta" "$body"
}

function test_should_send_env_and_ports_when_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --ports 8080/http,22/tcp --env FOO=bar --start-cmd python,main.py
  _pod_update >/dev/null 2>&1
  assert_equals "bar" "$(jq -r '.env.FOO' "$body")"
  assert_equals "8080/http" "$(jq -r '.ports[0]' "$body")"
  assert_equals "python main.py" "$(jq -r '.args' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_pod_update_has_no_fields() {
  rp::http() { :; }
  rp::args_parse pod1
  (_pod_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_post_action_body_when_lifecycle_verb_given() {
  local meta body
  meta="$(mktemp)"
  body="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$meta"
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse p1
  _pod_simple stop >/dev/null 2>&1
  assert_equals "POST /pods/p1/action" "$(cat "$meta")"
  assert_equals "stop" "$(jq -r '.action' "$body")"
  rp::http() { :; }
  rm -f "$meta" "$body"
}

function test_should_set_registry_when_create_flag_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse pod1 --image img --name foo --gpu "RTX 4090" --registry reg-123
  _pod_create >/dev/null 2>&1
  assert_equals "reg-123" "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_omit_registry_when_create_flag_absent() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse pod1 --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("registry")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_interruptible_and_bid_when_bid_per_gpu_given() {
  local body
  body="$(mktemp)"
  rp::http_soft() {
    _RP_CURL_STATUS=200
    printf '%s' "${4:-}" >"$body"
    printf '{"id":"pod1"}' >"$1"
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --bid-per-gpu 0.20
  local out
  out="$(_pod_create 2>/dev/null)"
  assert_equals "pod1" "$out"
  assert_equals "true" "$(jq -r '.interruptible' "$body")"
  assert_equals "0.20" "$(jq -r '.bidPerGpu' "$body")"
  rp::http_soft() { :; }
  rm -f "$body"
}

function test_should_set_interruptible_true_when_flag_given_alone() {
  local body
  body="$(mktemp)"
  rp::http_soft() {
    _RP_CURL_STATUS=200
    printf '%s' "${4:-}" >"$body"
    printf '{"id":"pod1"}' >"$1"
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --interruptible
  local out
  out="$(_pod_create 2>/dev/null)"
  assert_equals "pod1" "$out"
  assert_equals "true" "$(jq -r '.interruptible' "$body")"
  assert_equals "false" "$(jq -r 'has("bidPerGpu")' "$body")"
  rp::http_soft() { :; }
  rm -f "$body"
}

function test_should_fall_back_to_graphql_when_v2_rejects_spot() {
  local body
  body="$(mktemp)"
  rp::resource_existing() { return 1; }
  rp::http_soft() {
    _RP_CURL_STATUS=422
    printf '%s' "${4:-}" >"$body"
    printf '{"detail":[{"loc":["body","interruptible"],"msg":"extra forbidden"}]}' >"$1"
  }
  rp::graphql() {
    printf '{"podRentInterruptable":{"id":"podG"}}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --bid-per-gpu 0.20
  local out
  out="$(_pod_create 2>/dev/null)"
  assert_equals "podG" "$out"
  assert_contains "interruptible" "$(cat "$body")"
  rp::resource_existing() { :; }
  rp::http_soft() { :; }
  rp::graphql() { :; }
  rm -f "$body"
}

function test_should_omit_spot_fields_when_not_requested() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("interruptible")' "$body")"
  assert_equals "false" "$(jq -r 'has("bidPerGpu")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_bid_per_gpu_is_zero() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --bid-per-gpu 0
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_bid_per_gpu_not_a_number() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --bid-per-gpu abc
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_set_registry_when_update_flag_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --registry reg-456
  _pod_update >/dev/null 2>&1
  assert_equals "reg-456" "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_send_cpu_block_when_cpu_flavor_and_vcpu_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --cpu-flavor cpu5c --vcpu 8
  _pod_create >/dev/null 2>&1
  assert_equals "cpu5c" "$(jq -r '.cpu.id' "$body")"
  assert_equals "8" "$(jq -r '.cpu.vcpuCount' "$body")"
  assert_equals "false" "$(jq -r 'has("gpu")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_both_gpu_and_cpu_flavor_given() {
  rp::http() { :; }
  rp::args_parse --image img --gpu "RTX 4090" --cpu-flavor cpu5c --vcpu 4
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_cpu_flavor_without_vcpu() {
  rp::http() { :; }
  rp::args_parse --image img --cpu-flavor cpu5c
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_vcpu_without_cpu_flavor() {
  rp::http() { :; }
  rp::args_parse --image img --vcpu 4
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_vcpu_not_power_of_two() {
  rp::http() { :; }
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 6
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_cpu_pod_asks_for_persistent_volume() {
  rp::http() { :; }
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 4 --volume-gb 20
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_allow_network_volume_on_cpu_pod() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --cpu-flavor cpu5c --vcpu 4 --network-volume-id nv1
  _pod_create >/dev/null 2>&1
  assert_equals "nv1" "$(jq -r '.mounts.network[0].volumeId' "$body")"
  assert_equals "cpu5c" "$(jq -r '.cpu.id' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_volume_gb_and_network_volume_id_given() {
  # Sentinel: the guard must exit before any request — if rp::http runs, the
  # subshell exits 99 and assert_exit_code 2 fails.
  rp::http() {
    echo "rp::http called before the mount guard" >&2
    exit 99
  }
  rp::args_parse --image img --volume-gb 20 --network-volume-id nv1
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

function test_should_die_when_create_missing_name() {
  rp::http() { :; }
  rp::args_parse --image img --gpu "RTX 4090"
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_create_has_neither_gpu_nor_cpu_flavor() {
  rp::http() { :; }
  rp::args_parse --image img --name foo
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_set_network_mount_path_when_volume_path_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --network-volume-id nv1 --volume-path /data
  _pod_create >/dev/null 2>&1
  assert_equals "nv1" "$(jq -r '.mounts.network[0].volumeId' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.network[0].path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_persistent_mount_path_when_volume_path_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --volume-gb 20 --volume-path /data
  _pod_create >/dev/null 2>&1
  assert_equals "20" "$(jq -r '.mounts.persistent.size' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_global_networking_true_on_create() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --global-networking true
  _pod_create >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.globalNetworking' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_global_networking_false_on_create() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --global-networking false
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r '.globalNetworking' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_omit_global_networking_when_absent_on_create() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("globalNetworking")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_global_networking_true_with_cpu_flavor() {
  rp::http() { :; }
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 4 --global-networking true
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_allow_global_networking_false_with_cpu_flavor() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --cpu-flavor cpu5c --vcpu 4 --global-networking false
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r '.globalNetworking' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_on_invalid_global_networking_token() {
  rp::http() { :; }
  rp::args_parse --image img --global-networking yes
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_set_locked_true_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --locked true
  _pod_update >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.locked' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_locked_false_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --locked false
  _pod_update >/dev/null 2>&1
  assert_equals "false" "$(jq -r '.locked' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_on_invalid_locked_token() {
  rp::http() { :; }
  rp::args_parse pod1 --locked maybe
  (_pod_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_set_global_networking_false_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --global-networking false
  _pod_update >/dev/null 2>&1
  assert_equals "false" "$(jq -r '.globalNetworking' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_persistent_path_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{}'
  }
  rp::args_parse pod1 --volume-gb 20 --volume-path /data
  _pod_update >/dev/null 2>&1
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# rp::api_stream recording double: captures "<plane> <path> <leid>" into $cap.
function test_should_route_pod_logs_to_stream() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_pod logs p1 >/dev/null 2>&1
  assert_equals "rest /pods/p1/logs " "$(<"$cap")"
  rm -f "$cap"
}

function test_should_compose_pod_logs_flags_onto_query() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_pod logs p1 --source container --tail 50 >/dev/null 2>&1
  assert_equals "rest /pods/p1/logs?source=container&tail=50 " "$(<"$cap")"
  rm -f "$cap"
}

function test_should_pass_since_timestamp_through_to_pod_logs() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_pod logs p1 --since 2026-08-01T00:00:00Z >/dev/null 2>&1
  assert_contains "since=2026-08-01T00:00:00Z" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_pass_last_event_id_as_header_not_query() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_pod logs p1 --last-event-id 2026-08-01T00:00:00Z >/dev/null 2>&1
  assert_equals "rest /pods/p1/logs 2026-08-01T00:00:00Z" "$(<"$cap")"
  assert_not_contains "last-event-id=" "$(<"$cap")"
  rm -f "$cap"
}

function test_should_die_on_invalid_source_in_pod_logs() {
  rp::api_stream() { :; }
  (rp::cmd_pod logs p1 --source bogus >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_on_tail_over_bound_in_pod_logs() {
  rp::api_stream() { :; }
  (rp::cmd_pod logs p1 --tail 9999 >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_pass_tail_bounds_in_pod_logs() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_pod logs p1 --tail 0 >/dev/null 2>&1
  assert_contains "/pods/p1/logs?tail=0 " "$(<"$cap")"
  rp::cmd_pod logs p1 --tail 5000 >/dev/null 2>&1
  assert_contains "/pods/p1/logs?tail=5000 " "$(<"$cap")"
  rm -f "$cap"
}

function test_should_exit_usage_when_pod_logs_missing_id() {
  rp::api_stream() { :; }
  (rp::cmd_pod logs >/dev/null 2>&1)
  assert_exit_code 2
}

# main-shell dispatcher call so the public rp::cmd_pod entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_pod help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp pod" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing: exercise every public verb through the dispatcher so the
# rp::cmd_pod case branches register coverage (bashunit skips $(...) subshells).
function test_should_route_each_pod_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{"id":"p1"}'; fi
  }
  rp::cmd_pod list >/dev/null 2>&1
  assert_contains "GET /pods" "$(<"$cap")"
  rp::cmd_pod get p1 >/dev/null 2>&1
  assert_contains "GET /pods/p1" "$(<"$cap")"
  rp::cmd_pod create --image img --name foo --gpu "RTX 4090" >/dev/null 2>&1
  assert_contains "POST /pods" "$(<"$cap")"
  rp::cmd_pod update p1 --volume-gb 5 >/dev/null 2>&1
  assert_contains "PATCH /pods/p1" "$(<"$cap")"
  rp::cmd_pod start p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/action" "$(<"$cap")"
  rp::cmd_pod stop p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/action" "$(<"$cap")"
  rp::cmd_pod reset p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/action" "$(<"$cap")"
  rp::cmd_pod restart p1 >/dev/null 2>&1
  assert_contains "POST /pods/p1/action" "$(<"$cap")"
  rp::cmd_pod delete p1 >/dev/null 2>&1
  assert_contains "DELETE /pods/p1" "$(<"$cap")"
  rm -f "$cap"
}

function test_create_sets_template_id_and_omits_image() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --name foo --gpu "RTX 4090" --template-id tpl_abc
  _pod_create >/dev/null 2>&1
  assert_equals "tpl_abc" "$(jq -r '.templateId' "$body")"
  assert_equals "false" "$(jq -r 'has("image")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_create_requires_image_or_template_id() {
  rp::http() { :; }
  rp::args_parse --name foo --gpu "RTX 4090"
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_set_startSsh_true_when_create_flag_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --ssh
  _pod_create >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.startSsh' "$body")"
  assert_equals "boolean" "$(jq -r '.startSsh|type' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_omit_startSsh_when_create_flag_absent() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("startSsh")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_min_cuda_version_when_create_flag_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --min-cuda-version 12.1
  _pod_create >/dev/null 2>&1
  assert_equals "12.1" "$(jq -r '.gpu.minCudaVersion' "$body")"
  assert_equals "string" "$(jq -r '.gpu.minCudaVersion|type' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_omit_min_cuda_version_when_create_flag_absent() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r '.gpu | has("minCudaVersion")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_on_invalid_min_cuda_version_integer() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --min-cuda-version 12
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_on_invalid_min_cuda_version_text() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --min-cuda-version abc
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_on_invalid_min_cuda_version_for_cpu_pod() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --cpu-flavor cpu5c --vcpu 4 --min-cuda-version abc
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_compute_type_gpu_without_gpu() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --compute-type GPU
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_compute_type_cpu_without_cpu_flavor() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --compute-type CPU --vcpu 4
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_compute_type_cpu_without_vcpu() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --compute-type CPU --cpu-flavor cpu5c
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_on_invalid_compute_type_value() {
  rp::http() { :; }
  rp::args_parse --image img --name foo --compute-type TPU --gpu "RTX 4090"
  (_pod_create >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_send_gpu_block_when_compute_type_gpu_with_gpu() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --compute-type GPU --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "RTX 4090" "$(jq -r '.gpu.id' "$body")"
  assert_equals "false" "$(jq -r 'has("cpu")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_send_cpu_block_when_compute_type_cpu_with_cpu_flags() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --compute-type CPU --cpu-flavor cpu5c --vcpu 8
  _pod_create >/dev/null 2>&1
  assert_equals "cpu5c" "$(jq -r '.cpu.id' "$body")"
  assert_equals "8" "$(jq -r '.cpu.vcpuCount' "$body")"
  assert_equals "false" "$(jq -r 'has("gpu")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_set_support_public_ip_when_public_ip_flag_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then printf '{"pods":[]}'; return; fi
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090" --public-ip
  _pod_create >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.supportPublicIp' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_omit_support_public_ip_when_flag_absent() {
  local body
  body="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then printf '{"pods":[]}'; return; fi
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --name foo --gpu "RTX 4090"
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("supportPublicIp")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_filter_pods_by_public_ip_when_list_flag_given() {
  rp::http() {
    printf '%s' '{"pods":[
      {"id":"pub1","name":"a","image":"i","status":"RUNNING","cost":1,"publicIp":"1.2.3.4"},
      {"id":"priv1","name":"b","image":"i","status":"RUNNING","cost":1,"publicIp":""},
      {"id":"init1","name":"c","image":"i","status":"PROVISIONING","cost":1}
    ]}'
  }
  local out
  out="$(rp::args_parse --public-ip; _pod_list 2>/dev/null)"
  assert_contains "pub1" "$out"
  [[ "$out" == *"priv1"* ]] && fail "private-IP pod should be filtered out"
  [[ "$out" == *"init1"* ]] && fail "pod without publicIp should be filtered out"
  rp::http() { :; }
}

function test_should_list_all_pods_when_public_ip_flag_absent() {
  rp::http() {
    printf '%s' '{"pods":[
      {"id":"pub1","name":"a","image":"i","status":"RUNNING","cost":1,"publicIp":"1.2.3.4"},
      {"id":"priv1","name":"b","image":"i","status":"RUNNING","cost":1,"publicIp":""}
    ]}'
  }
  local out
  out="$(rp::args_parse; _pod_list 2>/dev/null)"
  assert_contains "pub1" "$out"
  assert_contains "priv1" "$out"
  rp::http() { :; }
}
