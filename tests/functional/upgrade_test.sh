#!/usr/bin/env bash
# tests/functional/upgrade_test.sh
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _RP_COMMON _RP_ARGS
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/commands/upgrade.sh"
  eval "$_opts"
}

function set_up() {
  OUT="$(mktemp)"
  ERR="$(mktemp)"
  CURL_ARGS="$(mktemp)"
  BASH_ARGS="$(mktemp)"
  # rp::version lives in bin/rp, not lib; stub it.
  rp::version() { printf '%s' "1.0.0"; }
  # curl mock: capture argv, write a stub installer to the -o file, return 0.
  curl() {
    printf '%s\n' "$*" >>"$CURL_ARGS"
    local out=""
    while (($#)); do
      case "$1" in
      -o)
        out="$2"
        shift 2
        ;;
      *) shift ;;
      esac
    done
    [[ -n "$out" ]] && printf '%s\n' '#!/usr/bin/env bash' >"$out"
    return 0
  }
  # bash mock: record the installer argv; the installer is a stub so nothing runs.
  bash() { printf '%s\n' "$*" >>"$BASH_ARGS"; }
}

function tear_down() {
  rm -f "$OUT" "$ERR" "$CURL_ARGS" "$BASH_ARGS"
  unset -f curl bash
}

function test_should_print_usage_when_help_given() {
  rp::cmd_upgrade --help >"$OUT" 2>/dev/null
  assert_contains "Usage: rp upgrade" "$(<"$OUT")"
}

function test_should_download_main_installer_when_no_version() {
  rp::cmd_upgrade >"$OUT" 2>/dev/null
  assert_file_exists "$BASH_ARGS"
  assert_contains "main/install.sh" "$(<"$CURL_ARGS")"
  assert_not_contains "--version" "$(<"$BASH_ARGS")"
}

function test_should_download_pinned_installer_when_version_given() {
  rp::cmd_upgrade --version 1.2.3 >"$OUT" 2>/dev/null
  assert_contains "v1.2.3/install.sh" "$(<"$CURL_ARGS")"
  assert_contains "--version 1.2.3" "$(<"$BASH_ARGS")"
}

function test_should_report_current_then_target_version() {
  rp::cmd_upgrade --version 1.2.3 >/dev/null 2>"$ERR"
  assert_contains "1.0.0 -> 1.2.3" "$(<"$ERR")"
}

function test_should_die_when_installer_download_fails() {
  curl() {
    printf '%s\n' "$*" >>"$CURL_ARGS"
    return 1
  }
  (rp::cmd_upgrade >/dev/null 2>&1)
  assert_exit_code 1
}

function test_should_die_with_message_when_installer_download_fails() {
  curl() {
    printf '%s\n' "$*" >>"$CURL_ARGS"
    return 1
  }
  local err
  err="$(rp::cmd_upgrade 2>&1 >/dev/null || true)"
  assert_contains "installer download failed" "$err"
}
