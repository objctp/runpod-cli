#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/doc.sh"
  eval "$_opts"
}

function set_up() {
  :
}

# Verbless commands carry their whole block in the file-header intro, so they
# are allowed to have no per-verb `# doc:` blocks.
VERBLESS=" api upgrade endpoint doc "

function _cmd_names() {
  local f
  for f in "$RP_ROOT"/commands/*.sh; do
    basename "$f" .sh
  done
}

function _is_verbless() {
  [[ " $VERBLESS " == *" $1 "* ]]
}

# A summary must be non-empty and end with a full stop.
function _assert_summary_shape() {
  local s="$1"
  assert_not_empty "$s"
  assert_equals "." "${s: -1}"
}

# Every header line in a block must belong to the fixed vocabulary, appear at
# most once, and follow the canonical order.
function _assert_headers() {
  local body="$1" h prev=0 violations="" dup=0
  local -A idx=([Usage]=1 [Arguments]=2 [Options]=3 [Notes]=4 [Examples]=5 [API]=6)
  local -a seen=()
  while IFS= read -r line; do
    h="${line%%:*}"
    [[ -n "${idx[$h]:-}" ]] || continue
    if ((${idx[$h]} < prev)); then violations+=" order:$h"; fi
    dup=0
    local s
    for s in "${seen[@]}"; do
      [[ "$s" == "$h" ]] && dup=1
    done
    if ((dup)); then violations+=" dup:$h"; fi
    seen+=("$h")
    prev=${idx[$h]}
  done <<<"$body"
  assert_equals "" "$violations"
}

function test_every_command_intro_summary_is_well_formed() {
  local f name sum
  for name in $(_cmd_names); do
    f="$RP_ROOT/commands/$name.sh"
    sum="$(rp::doc_intro_summary "$f")"
    _assert_summary_shape "$sum"
    assert_equals 1 "$([ ${#sum} -le 62 ] && echo 1 || echo 0)" \
      "intro summary of $name is ${#sum} chars (>62): $sum"
  done
}

function test_verbless_four_have_intro_usage_and_summary() {
  local name f body
  for name in $VERBLESS; do
    f="$RP_ROOT/commands/$name.sh"
    body="$(rp::doc_intro "$f")"
    assert_contains "Usage:" "$body"
  done
}

function test_verb_block_has_summary_usage_and_valid_headers() {
  local f name verb body first
  for name in $(_cmd_names); do
    _is_verbless "$name" && continue
    f="$RP_ROOT/commands/$name.sh"
    for verb in $(rp::doc_verbs "$f"); do
      body="$(rp::doc_verb_marker "$f" "$verb")"
      assert_not_empty "$body" || continue
      first="$(printf '%s\n' "$body" | awk 'NF{print;exit}')"
      _assert_summary_shape "$first"
      assert_contains "Usage:" "$body"
      _assert_headers "$body"
    done
  done
}

function test_registry_delegations_subverbs_documented() {
  local f="$RP_ROOT/commands/registry.sh" sv body first
  for sv in $(rp::doc_subverbs "$f" delegations); do
    body="$(rp::doc_verb_marker "$f" "delegations $sv")"
    assert_not_empty "$body" || continue
    first="$(printf '%s\n' "$body" | awk 'NF{print;exit}')"
    _assert_summary_shape "$first"
    assert_contains "Usage:" "$body"
    _assert_headers "$body"
  done
}
