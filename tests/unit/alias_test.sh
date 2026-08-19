#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  eval "$_opts"
}

# Each test asserts the generic key-copy alias map: an alias populates the
# canonical key when the canonical is absent, and never overwrites an explicit
# canonical value.

function test_should_copy_alias_into_canonical_when_canonical_absent() {
  rp::args_parse --gpu-id "RTX 4090"
  assert_equals "RTX 4090" "$(rp::args_get gpu)"
}

function test_should_not_overwrite_explicit_canonical_with_alias() {
  rp::args_parse --gpu "RTX 3090" --gpu-id "RTX 4090"
  assert_equals "RTX 3090" "$(rp::args_get gpu)"
}

function test_should_alias_data_center_ids_to_dc() {
  rp::args_parse --data-center-ids "EU-RO-1"
  assert_equals "EU-RO-1" "$(rp::args_get dc)"
}

function test_should_alias_container_disk_in_gb_to_container_disk_gb() {
  rp::args_parse --container-disk-in-gb 100
  assert_equals "100" "$(rp::args_get container-disk-gb)"
}

function test_should_alias_volume_in_gb_to_volume_gb() {
  rp::args_parse --volume-in-gb 200
  assert_equals "200" "$(rp::args_get volume-gb)"
}

function test_should_alias_volume_mount_path_to_volume_path() {
  rp::args_parse --volume-mount-path /data
  assert_equals "/data" "$(rp::args_get volume-path)"
}

function test_should_alias_registry_auth_id_to_registry() {
  rp::args_parse --registry-auth-id reg-123
  assert_equals "reg-123" "$(rp::args_get registry)"
}

function test_should_alias_cloud_type_to_cloud() {
  rp::args_parse --cloud-type COMMUNITY
  assert_equals "COMMUNITY" "$(rp::args_get cloud)"
}

function test_should_alias_docker_args_to_start_cmd() {
  rp::args_parse --docker-args "python main.py"
  assert_equals "python main.py" "$(rp::args_get start-cmd)"
}

function test_should_alias_docker_start_cmd_to_docker_cmd() {
  rp::args_parse --docker-start-cmd "a,b"
  assert_equals "a,b" "$(rp::args_get docker-cmd)"
}

function test_should_leave_env_unaliased() {
  rp::args_parse --env "FOO=bar"
  assert_equals "FOO=bar" "$(rp::args_get env)"
  # --env must NOT be aliased to anything; the canonical key stays as given.
  assert_equals "" "$(rp::args_get env-json 2>/dev/null)"
}

function test_should_define_all_nine_key_copy_aliases() {
  local got
  got="$(printf '%s\n' "${RP_FLAG_ALIASES[@]}" | sort | tr '\n' ' ')"
  local want="cloud-type:cloud container-disk-in-gb:container-disk-gb data-center-ids:dc docker-args:start-cmd docker-start-cmd:docker-cmd gpu-id:gpu registry-auth-id:registry volume-in-gb:volume-gb volume-mount-path:volume-path"
  want="$(printf '%s\n' "$want" | sort | tr '\n' ' ')"
  assert_equals "$want" "$got"
  assert_equals 9 "$(printf '%s\n' "${RP_FLAG_ALIASES[@]}" | wc -l | tr -d ' ')"
}
