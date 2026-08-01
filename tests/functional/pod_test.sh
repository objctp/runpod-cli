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
  rp::args_parse pod1 --image img --registry reg-123
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
  rp::args_parse pod1 --image img
  _pod_create >/dev/null 2>&1
  assert_equals "false" "$(jq -r 'has("registry")' "$body")"
  rp::http() { :; }
  rm -f "$body"
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
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 8
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
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 4 --network-volume-id nv1
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

function test_should_set_network_mount_path_when_volume_path_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"pod1"}'
  }
  rp::args_parse --image img --network-volume-id nv1 --volume-path /data
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
  rp::args_parse --image img --volume-gb 20 --volume-path /data
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
  rp::args_parse --image img --global-networking true
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
  rp::args_parse --image img --global-networking false
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
  rp::args_parse --image img
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
  rp::args_parse --image img --cpu-flavor cpu5c --vcpu 4 --global-networking false
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
  rp::cmd_pod create --image img >/dev/null 2>&1
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
