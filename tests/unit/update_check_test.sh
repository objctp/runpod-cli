#!/usr/bin/env bash
# tests/unit/update_check_test.sh
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _RP_COMMON _RP_UPDATE_CHECK
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/update_check.sh"
  eval "$_opts"
}

# --- version comparison ---

function test_should_report_behind_when_newer_exists() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.4.0
  assert_exit_code 0
}

function test_should_not_report_behind_when_equal() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.2.3
  assert_exit_code 1
}

function test_should_report_behind_on_patch_bump() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.2.4
  assert_exit_code 0
}

# Leading-zero components must compare in base 10, not trip bash's octal
# arithmetic (which silently evaluated to false).
function test_should_report_behind_with_leading_zero_component() {
  RP_VERSION=1.08.0
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.10.0
  assert_exit_code 0
}

function test_should_report_behind_with_leading_zero_over_nine_patch() {
  RP_VERSION=1.08.0
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.9.0
  assert_exit_code 0
}

function test_should_treat_leading_zero_as_equal_when_versions_match() {
  RP_VERSION=1.08.0
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.8.0
  assert_exit_code 1
}

function test_should_not_report_behind_for_dev_build() {
  RP_VERSION=0.0.0-dev
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.0.0
  assert_exit_code 1
}

function test_should_not_report_behind_for_git_describe() {
  RP_VERSION=v1.2.3-5-gabcdef
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_version_is_behind 1.4.0
  assert_exit_code 1
}

# --- install-method detection (path driven) ---

function test_should_detect_bash_install_from_rp_dir() {
  local bin_dir target method
  bin_dir="$(mktemp -d)"
  target="$bin_dir/.rp/bin/rp"
  mkdir -p "$(dirname "$target")"
  printf '#!/bin/sh\n' >"$target"
  chmod +x "$target"
  ln -s "$target" "$bin_dir/rp"
  method="$(PATH="$bin_dir:$PATH" rp::_detect_install_method)"
  assert_equals "bash" "$method"
}

function test_should_detect_brew_install_from_cellar() {
  local bin_dir target method
  bin_dir="$(mktemp -d)"
  target="$bin_dir/Cellar/runpod-cli/1.2.3/bin/rp"
  mkdir -p "$(dirname "$target")"
  printf '#!/bin/sh\n' >"$target"
  chmod +x "$target"
  ln -s "$target" "$bin_dir/rp"
  method="$(PATH="$bin_dir:$PATH" rp::_detect_install_method)"
  assert_equals "brew" "$method"
}

function test_should_detect_npm_install_from_node_modules() {
  local bin_dir target method
  bin_dir="$(mktemp -d)"
  target="$bin_dir/node_modules/runpod-cli/bin/rp"
  mkdir -p "$(dirname "$target")"
  printf '#!/bin/sh\n' >"$target"
  chmod +x "$target"
  ln -s "$target" "$bin_dir/rp"
  method="$(PATH="$bin_dir:$PATH" rp::_detect_install_method)"
  assert_equals "npm" "$method"
}

function test_should_detect_unknown_when_rp_absent() {
  rp::_detect_install_method() { printf '%s' unknown; }
  assert_equals "unknown" "$(rp::_detect_install_method)"
}

# --- notice text names the right upgrade command ---

function test_notice_recommends_rp_upgrade_for_bash() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_detect_install_method() { printf '%s' bash; }
  local out
  out="$(rp::_print_update_notice 1.4.0 2>&1 >/dev/null)"
  assert_contains "run 'rp upgrade'" "$out"
}

function test_notice_recommends_npm_update_for_npm() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_detect_install_method() { printf '%s' npm; }
  local out
  out="$(rp::_print_update_notice 1.4.0 2>&1 >/dev/null)"
  assert_contains "npm update -g runpod-cli" "$out"
}

function test_notice_recommends_brew_upgrade_for_brew() {
  RP_VERSION=1.2.3
  rp::version() { printf '%s' "$RP_VERSION"; }
  rp::_detect_install_method() { printf '%s' brew; }
  local out
  out="$(rp::_print_update_notice 1.4.0 2>&1 >/dev/null)"
  assert_contains "brew upgrade runpod-cli" "$out"
}

# --- inherit_errexit hardening (#51) ---

# A malformed release body (proxy garbage, partial download) must degrade to
# "no update seen" — not silently kill the CLI at startup under set -e.
function test_refresh_degrades_on_malformed_release_body() {
  curl() {
    local out
    while (($#)); do
      case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      *) shift ;;
      esac
    done
    printf '<html>gateway garbage</html>' >"$out"
    printf '200'
  }
  local cache lock out rc
  cache="$(mktemp -u)"
  lock="$(mktemp -u)"
  out="$(
    set -euo pipefail
    shopt -s inherit_errexit
    rp::_update_check_refresh "$cache" "$lock" 2>&1
  )" && rc=0 || rc=$?
  assert_equals 0 "$rc"
  assert_equals "" "$out"
  if [[ -f "$cache" || -d "$lock" ]]; then
    rm -rf "$cache" "$lock"
    return 1
  fi
}

# `command -v rp` exits 1 when rp is not on PATH (e.g. `bash bin/rp` from a
# checkout); the empty result is the normal not-installed case.
function test_detect_install_method_unknown_when_rp_not_on_path() {
  local out rc
  out="$(
    set -euo pipefail
    shopt -s inherit_errexit
    PATH=/nonexistent rp::_detect_install_method 2>&1
  )" && rc=0 || rc=$?
  assert_equals 0 "$rc"
  assert_equals "unknown" "$out"
}
