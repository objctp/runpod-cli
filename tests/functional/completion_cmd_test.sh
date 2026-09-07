#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/bin/rp"
  eval "$_opts"
}

function test_should_print_bash_artefact() {
  local out
  out="$(rp::main completion bash)"
  assert_contains "complete -F _rp_bash_lazy rp" "$out"
  assert_contains "rp.bash" "$out"
}

function test_should_print_zsh_artefact() {
  local out
  out="$(rp::main completion zsh)"
  assert_contains "#compdef rp" "$out"
  assert_contains "compdef _rp rp" "$out"
}

function test_should_exit_two_on_unknown_verb() {
  (rp::main completion fish >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_print_help() {
  local out
  out="$(rp::main completion --help)"
  assert_contains "Usage: rp completion <bash|zsh>" "$out"
}
