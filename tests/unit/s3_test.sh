#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  # bin/rp (sourced by rp_test) may have set lib/s3.sh's guard; drop it so the
  # real s3 helpers are (re)defined here.
  unset _RP_S3 _RP_COMMON
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/s3.sh"
  eval "$_opts"
}

function set_up() {
  RUNPOD_S3_ACCESS_KEY="ak"
  RUNPOD_S3_SECRET_KEY="sk"
  CAP="$(mktemp)"
  AWS_CAP="$CAP"
  # aws double: record the full argv space-joined to AWS_CAP so substring
  # assertions can inspect the synthesised s3 command.
  aws() {
    printf '%s\n' "$*" >"$AWS_CAP"
  }
}

function tear_down() {
  rm -f "$CAP"
  unset -f aws
}

function test_should_lower_case_when_region_derived() {
  assert_equals "eu-ro-1" "$(_s3_region EU-RO-1)"
}

function test_should_build_endpoint_when_dc_given() {
  assert_equals "https://s3api-eu-ro-1.runpod.io/" "$(_s3_endpoint EU-RO-1)"
}

function test_should_export_aws_creds_when_env_set() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  _s3_env
  assert_equals "ak" "$AWS_ACCESS_KEY_ID"
  assert_equals "sk" "$AWS_SECRET_ACCESS_KEY"
}

function test_should_exit_three_when_s3_creds_unset() {
  unset RUNPOD_S3_ACCESS_KEY
  (_s3_env >/dev/null 2>&1)
  assert_exit_code 3
}

function test_should_sync_to_prefix_when_given() {
  rp::s3_sync /src mybucket EU-RO-1 models >/dev/null
  local argv
  argv="$(<"$CAP")"
  assert_contains "s3 sync" "$argv"
  assert_contains "/src" "$argv"
  assert_contains "s3://mybucket/models/" "$argv"
  assert_contains "eu-ro-1" "$argv"
  assert_contains "https://s3api-eu-ro-1.runpod.io/" "$argv"
}

function test_should_sync_to_bucket_root_when_no_prefix() {
  rp::s3_sync /src mybucket EU-RO-1 >/dev/null
  local argv
  argv="$(<"$CAP")"
  assert_contains "s3://mybucket/" "$argv"
}

function test_should_ls_remote_path_when_given() {
  rp::s3_ls mybucket EU-RO-1 sub/dir >/dev/null
  local argv
  argv="$(<"$CAP")"
  assert_contains "s3 ls" "$argv"
  assert_contains "s3://mybucket/sub/dir/" "$argv"
}

function test_should_ls_bucket_root_when_no_prefix() {
  rp::s3_ls mybucket EU-RO-1 >/dev/null
  local argv
  argv="$(<"$CAP")"
  assert_contains "s3://mybucket/" "$argv"
}
