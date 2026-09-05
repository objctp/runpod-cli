#!/usr/bin/env bash
# Semantics contract for `shopt -s inherit_errexit` (flipped in bin/rp after
# rp::check_runtime): a failing command inside $() aborts the substitution.
# Every test here runs in a subshell that mirrors bin/rp's options exactly.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  unset _RP_COMMON _RP_JSON
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/json.sh"
  eval "$_opts"
}

# Runs the snippet in a bin/rp-faithful subshell (same shell — not a child
# bash, which would not inherit set -e): errexit + nounset + pipefail +
# inherit_errexit. The capture is a PLAIN statement (not `&& rc || rc=$?`) —
# a guarded capture would put the substitution in an ignorable context, where
# bash ignores errexit inside $() even with inherit_errexit.
_rp_strict() {
  local snippet="$1" out err rc
  err="$(mktemp)"
  out="$(
    set -euo pipefail
    shopt -s inherit_errexit
    eval "$snippet" 2>"$err"
  )"
  rc=$?
  RP_OUT="$out"
  RP_ERR="$(cat "$err")"
  rm -f "$err"
  return "$rc"
}

# Statement context: an interior failure aborts the substitution; output
# written before the abort is still captured (partial output, failed status).
function test_strict_substitution_aborts_on_interior_failure() {
  _rp_strict 'printf a; false; printf b'
  assert_exit_code 1
  assert_equals "a" "$RP_OUT"
}

# Statement context, nested: an unguarded failing substitution aborts the
# enclosing subshell too (the partial output went into $x and is lost with it).
function test_strict_unguarded_substitution_fails_closed() {
  _rp_strict 'x="$(printf a; false; printf b)"; printf "%s" "$x"'
  assert_exit_code 1
  assert_equals "" "$RP_OUT"
}

# Ignorable context (`||`, `if`, `&&`): bash IGNORES errexit inside $() even
# with inherit_errexit — the substitution runs to completion and pipefail's
# last-command status decides. This is why the wave's `x="$(cmd)" || die`
# pattern behaves identically before and after the flip.
function test_guarded_assignment_runs_to_completion_in_ignorable_context() {
  _rp_strict 'v="$(printf a; false; printf b)" || true; printf "%s" "${v:-}"'
  assert_successful_code "$?"
  assert_equals "ab" "$RP_OUT"
}

# The blessed fail-closed call-site pattern from the #31-#49 wave must keep
# dying (not silently yielding empty) with the option on.
function test_fail_closed_call_site_still_dies_under_flip() {
  _rp_strict 'v="$(false)" || rp::die "boom"'
  assert_exit_code 1
  assert_contains "boom" "$RP_ERR"
}

# The #32 seam: env_to_json returns 1 with the message on stderr; under the
# flip the abort happens inside the substitution, and the caller's || fires.
function test_env_pair_error_propagates_under_flip() {
  _rp_strict 'rp::env_to_json "=bad"'
  assert_equals 1 "$?"
  assert_contains "invalid --env pair" "$RP_ERR"
}
