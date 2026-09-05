#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/doc.sh"
  source "$RP_ROOT/commands/doc.sh"
  eval "$_opts"
}

function set_up() {
  :
}

# Verbless commands carry their whole block in the file-header intro, so they
# are allowed to have no per-verb `# doc:` blocks.
VERBLESS=" api upgrade doc "

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

# The serverless batch group follows the registry delegations convention: a
# group guard before the `case "$sub" in` block, so rp::doc_subverbs finds the
# sub-verbs and `rp doc serverless batch <verb>` resolves per verb.
function test_serverless_batch_subverbs_documented() {
  local f="$RP_ROOT/commands/serverless.sh" sv body first
  local subs
  subs="$(rp::doc_subverbs "$f" batch)"
  assert_contains "list" "$subs"
  assert_contains "finalize" "$subs"
  assert_contains "requests" "$subs"
  for sv in $subs; do
    body="$(rp::doc_verb_marker "$f" "batch $sv")"
    assert_not_empty "$body" || continue
    first="$(printf '%s\n' "$body" | awk 'NF{print;exit}')"
    _assert_summary_shape "$first"
    assert_contains "Usage:" "$body"
    _assert_headers "$body"
  done
}

# --- rp::cmd_doc dispatcher: not-found and ambiguous queries are usage errors ---

function test_doc_unknown_command_exits_two() {
  (rp::cmd_doc bogus-command >/dev/null 2>&1)
  assert_exit_code 2
}

function test_doc_unknown_verb_exits_two() {
  (rp::cmd_doc pod bogus-verb >/dev/null 2>&1)
  assert_exit_code 2
}

function test_doc_unknown_subverb_exits_two() {
  (rp::cmd_doc registry delegations bogus-verb >/dev/null 2>&1)
  assert_exit_code 2
}

# A prefix matching several commands must list the candidates and exit 2, never
# silently resolve to the alphabetically-first match ('s' hits serverless, ssh,
# ssh-key and stock).
function test_doc_ambiguous_prefix_lists_candidates_and_exits_two() {
  local err
  err="$( (rp::cmd_doc s 2>&1 >/dev/null))"
  assert_contains "ambiguous command prefix 's'" "$err"
  assert_contains "serverless" "$err"
  assert_contains "ssh-key" "$err"
  assert_contains "stock" "$err"
  (rp::cmd_doc s >/dev/null 2>&1)
  assert_exit_code 2
}

# A unique prefix still resolves (no regression from the ambiguity guard).
function test_doc_unique_prefix_resolves() {
  local out
  out="$(rp::cmd_doc serv 2>/dev/null)"
  assert_contains "rp serverless" "$out"
}

function test_doc_exact_name_still_resolves() {
  local out
  out="$(rp::cmd_doc volume 2>/dev/null)"
  assert_contains "rp volume" "$out"
}
