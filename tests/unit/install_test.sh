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
  unset RP_UNAME RP_BASH_MAJOR RP_BASH_MINOR RP_CHECKSUM RP_LATEST_TAG || true
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

function test_should_pass_when_bash_at_least_five_point_one() {
  RP_BASH_MAJOR=5
  RP_BASH_MINOR=1
  rp_inst_bash_ok
  assert_successful_code "$?"
}

function test_should_pass_when_bash_major_six() {
  RP_BASH_MAJOR=6
  RP_BASH_MINOR=0
  rp_inst_bash_ok
  assert_successful_code "$?"
}

function test_should_exit_one_when_bash_is_five_point_zero() {
  RP_BASH_MAJOR=5
  RP_BASH_MINOR=0
  (rp_inst_bash_ok >/dev/null 2>&1)
  assert_exit_code 1
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

# --- rp_inst_member_is_unsafe (L5 tar member guard) ---

function test_should_flag_absolute_tar_member_as_unsafe() {
  rp_inst_member_is_unsafe "/etc/passwd"
  assert_successful_code "$?"
}

function test_should_flag_traversal_tar_member_as_unsafe() {
  rp_inst_member_is_unsafe "bin/../evil"
  assert_successful_code "$?"
  rp_inst_member_is_unsafe "../escape"
  assert_successful_code "$?"
  rp_inst_member_is_unsafe ".."
  assert_successful_code "$?"
}

function test_should_accept_relative_tar_member_as_safe() {
  rp_inst_member_is_unsafe "bin/rp"
  assert_exit_code 1
  rp_inst_member_is_unsafe "lib/common.sh"
  assert_exit_code 1
}

# --- rp_inst_ensure_path (Q-L4 whitespace guard) ---

function test_should_return_zero_when_dir_already_on_path() {
  rp_inst_ensure_path "/usr/local/bin" "/usr/local/bin:/bin"
  assert_successful_code "$?"
}

function test_should_skip_path_entry_when_dir_has_whitespace() {
  local home_dir rc
  home_dir="$(mktemp -d)"
  HOME="$home_dir"
  rc="$(rp_inst_ensure_path "/tmp/dir with space" 2>/dev/null || true)"
  assert_empty "$rc"
  [[ ! -f "$home_dir/.bashrc" ]]
  rm -rf "$home_dir"
}

# shellcheck disable=SC2030,SC2031 # the subshell export IS the isolation
# --- rp_inst_setup_completion ---

# Echo a fake install tree whose completions/ holds both artefacts.
function _completion_fake() {
  local fake
  fake="$(mktemp -d)"
  mkdir -p "$fake/completions"
  printf '# GENERATED artefact\ncomplete -F _rp rp\n' >"$fake/completions/rp.bash"
  printf '#compdef rp\n' >"$fake/completions/_rp"
  printf '%s\n' "$fake"
}

# Run the wiring under shell/home/uname overrides, against an explicit dir.
function _completion_wire() { # $1 shell, $2 uname, $3 fake-home, $4 completions dir
  local shell="$1" uname="$2" home="$3" dir="$4"
  (
    # shellcheck disable=SC2030,SC2031 # the subshell export IS the isolation
    export HOME="$home" SHELL="$shell" RP_UNAME="$uname"
    rp_inst_setup_completion "$dir" >/dev/null 2>&1
  )
}

function test_should_wire_bash_completion_into_bashrc_on_linux() {
  local home
  local home fake
  home="$(mktemp -d)"
  fake="$(_completion_fake)"
  _completion_wire /bin/bash Linux "$home" "$fake/completions"
  assert_contains "source \"$fake/completions/rp.bash\" # rp completion" "$(<"$home/.bashrc")"
  assert_contains '# added by rp installer' "$(<"$home/.bashrc")"
  rm -rf "$home" "$fake"
}

function test_should_wire_completion_idempotently() {
  local home fake before after
  home="$(mktemp -d)"
  fake="$(_completion_fake)"
  _completion_wire /bin/bash Linux "$home" "$fake/completions"
  before="$(grep -c 'rp completion' "$home/.bashrc")"
  _completion_wire /bin/bash Linux "$home" "$fake/completions"
  after="$(grep -c 'rp completion' "$home/.bashrc")"
  assert_equals "$before" "$after"
  rm -rf "$home" "$fake"
}

function test_should_wire_zsh_completion_into_zshrc() {
  local home
  local home fake
  home="$(mktemp -d)"
  fake="$(_completion_fake)"
  _completion_wire /bin/zsh Linux "$home" "$fake/completions"
  assert_contains 'completions/_rp' "$(<"$home/.zshrc")"
  assert_contains 'needs compinit' "$(<"$home/.zshrc")"
  rm -rf "$home" "$fake"
}

function test_should_prefer_bash_profile_on_darwin_when_it_exists() {
  local home
  local home fake
  home="$(mktemp -d)"
  fake="$(_completion_fake)"
  : >"$home/.bash_profile"
  _completion_wire /usr/local/bin/bash Darwin "$home" "$fake/completions"
  assert_file_exists "$home/.bash_profile"
  assert_contains 'completions/rp.bash' "$(<"$home/.bash_profile")"
  assert_file_not_exists "$home/.bashrc"
  rm -rf "$home" "$fake"
}

function test_should_fall_back_to_bashrc_on_darwin_without_profile() {
  local home
  local home fake
  home="$(mktemp -d)"
  fake="$(_completion_fake)"
  _completion_wire /bin/bash Darwin "$home" "$fake/completions"
  assert_contains 'completions/rp.bash' "$(<"$home/.bashrc")"
  rm -rf "$home" "$fake"
}

function test_should_skip_unknown_shells_quietly() {
  local home
  home="$(mktemp -d)"
  _completion_wire /usr/bin/fish Linux "$home"
  local count
  count="$(find "$home" -type f | grep -c . || true)"
  assert_equals "0" "$count"
  rm -rf "$home"
}

function test_should_noop_when_artefacts_missing() {
  local home fake
  home="$(mktemp -d)"
  fake="$(mktemp -d)"
  (
    # shellcheck disable=SC2030,SC2031 # the subshell export IS the isolation
    export HOME="$home" SHELL=/bin/bash RP_UNAME=Linux
    rp_inst_setup_completion "$fake/completions" >/dev/null 2>&1
  )
  assert_file_not_exists "$home/.bashrc"
  rm -rf "$home" "$fake"
}

function test_should_warn_not_fail_when_rc_unwritable() {
  local home msg
  home="$(mktemp -d)"
  msg="$(mktemp)"
  local fake
  fake="$(mktemp -d)"
  mkdir -p "$fake/completions"
  printf 'x\n' >"$fake/completions/rp.bash"
  printf 'x\n' >"$home/.bashrc"
  chmod 400 "$home/.bashrc"
  (
    # shellcheck disable=SC2030,SC2031 # the subshell export IS the isolation
    export HOME="$home" SHELL=/bin/bash RP_UNAME=Linux
    rp_inst_setup_completion "$fake/completions" 2>"$msg"
  )
  assert_equals "0" "$?"
  assert_contains "could not wire completion" "$(<"$msg")"
  chmod 600 "$home/.bashrc"
  rm -rf "$home" "$fake" "$msg"
}
