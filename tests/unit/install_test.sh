#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/install.sh"
  eval "$_opts"
}

# Reset the test-only override hooks before each test so they never leak between
# tests (bashunit may run --parallel).
function set_up() {
  unset RP_UNAME RP_BASH_MAJOR RP_CHECKSUM RP_LATEST_TAG || true
}

# --- rp_inst_os ---

function test_should_return_darwin_when_uname_darwin() {
  RP_UNAME=Darwin
  assert_equals "darwin" "$(rp_inst_os)"
}

function test_should_return_linux_when_uname_linux() {
  RP_UNAME=Linux
  assert_equals "linux" "$(rp_inst_os)"
}

function test_should_exit_one_when_os_unsupported() {
  RP_UNAME=FreeBSD
  (rp_inst_os >/dev/null 2>&1)
  assert_exit_code 1
}

# --- rp_inst_bash_ok ---

function test_should_pass_when_bash_major_five() {
  RP_BASH_MAJOR=5
  rp_inst_bash_ok
  assert_successful_code "$?"
}

function test_should_exit_one_when_bash_major_three() {
  RP_BASH_MAJOR=3
  (rp_inst_bash_ok >/dev/null 2>&1)
  assert_exit_code 1
}

# --- rp_inst_checksum_cmd ---

function test_should_return_sha256sum_when_override_set() {
  RP_CHECKSUM="sha256sum"
  assert_equals "sha256sum" "$(rp_inst_checksum_cmd)"
}

function test_should_return_shasum_with_flag_when_override_set() {
  RP_CHECKSUM="shasum -a 256"
  assert_equals "shasum -a 256" "$(rp_inst_checksum_cmd)"
}

# --- url builders ---

function test_should_build_download_url_when_version_given() {
  assert_equals \
    "https://github.com/objctp/runpod-cli/releases/download/0.1.0/rp-0.1.0.tar.gz" \
    "$(rp_inst_download_url 0.1.0)"
}

function test_should_build_checksum_url_when_version_given() {
  assert_equals \
    "https://github.com/objctp/runpod-cli/releases/download/0.1.0/SHA256SUMS" \
    "$(rp_inst_checksum_url 0.1.0)"
}

# --- rp_inst_resolve_version ---

function test_should_return_override_when_latest_tag_set() {
  RP_LATEST_TAG="2.3.4"
  assert_equals "2.3.4" "$(rp_inst_resolve_version)"
}

# --- rp_inst_on_path (search list passed explicitly to stay parallel-safe) ---

function test_should_match_when_dir_in_search() {
  rp_inst_on_path /somewhere/bin "/somewhere/bin:/usr/bin"
  assert_successful_code "$?"
}

function test_should_exit_one_when_dir_not_in_search() {
  rp_inst_on_path /nope "/usr/bin:/bin"
  assert_exit_code 1
}
