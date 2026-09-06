#!/usr/bin/env bash
# rp::completion_spec — the grammar emitter behind `rp _complete-spec`.
# The doc blocks in commands/*.sh are the single source of truth: this suite
# pins the TSV contract the completion generator (a later phase) consumes
# (v/u/f records) and the doc-coverage invariant the spec relies on (every
# case-arm verb has a `# doc:` block).
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/doc.sh"
  source "$RP_ROOT/lib/completion.sh"
}

# The spec is computed once and shared: the doc index caches per file anyway,
# but capturing the output once keeps every assertion on the same emission.
_RP_SPEC=""
function _spec() {
  [[ -n "$_RP_SPEC" ]] && return 0
  _RP_SPEC="$(rp::completion_spec)"
}

# First record whose fields equal the needle's (a description may follow the
# last tab); echoes the record so tests can assert on its tail too.
function _spec_line_with_prefix() {
  local prefix="$1" l
  _spec
  while IFS= read -r l; do
    [[ "$l" == "$prefix"* ]] && {
      printf '%s\n' "$l"
      return 0
    }
  done <<<"$_RP_SPEC"
  return 1
}

# Membership + success assertion in one step: the needle must be a
# field-complete record prefix.
function _spec_has() {
  _spec_line_with_prefix "$1" >/dev/null
  assert_equals "0" "$?"
}

# --- record shape ---

function test_should_emit_only_well_formed_records() {
  _spec
  local bad
  bad="$(grep -Ev $'^[vuf](\t[^\t]*)+$' <<<"$_RP_SPEC" | grep -v '^$' || true)"
  assert_equals "" "$bad"
}

function test_should_emit_records_with_exact_field_counts() {
  _spec
  local l n bad=""
  while IFS= read -r l; do
    n="$(awk -F'\t' '{print NF}' <<<"$l")"
    case "$l" in
    $'v\t*') [[ "$n" == 3 ]] || bad+="$l"$'\n' ;;
    $'u\t*') [[ "$n" == 4 ]] || bad+="$l"$'\n' ;;
    $'f\t*') [[ "$n" == 7 ]] || bad+="$l"$'\n' ;;
    esac
  done <<<"$_RP_SPEC"
  assert_equals "" "$bad"
}

# --- verb records ---

function test_should_emit_verb_records_for_case_arm_verbs() {
  _spec_has $'v\tpod\tcreate'
  _spec_has $'v\tpod\tlogs'
  _spec_has $'v\tserverless\trun'
}

function test_should_emit_group_verb_and_subverbs() {
  _spec_has $'v\tregistry\tdelegations'
  _spec_has $'v\tregistry\tdelegations list'
  _spec_has $'v\tserverless\tbatch finalize'
}

# --- flag records ---

function test_should_classify_value_and_bool_flags() {
  local l
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\tgpu\t')"
  assert_equals "0" "$?"
  assert_contains $'value\t' "$l"
  _spec_has $'f\tpod\tcreate\tssh\tbool'
  _spec_has $'f\tpod\tlist\tpublic-ip\tbool'
  _spec_has $'f\tpod\tlogs\tsource\tvalue'
}

# A description that wraps onto continuation lines must come back as ONE
# line, internal whitespace squeezed (regression: pod create's Options section
# truncated at the first continuation mentioning another flag).
function test_should_join_wrapped_descriptions_into_one_line() {
  local l
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\tinterruptible\t')"
  assert_equals "0" "$?"
  assert_contains "create a spot (interruptible) pod; the server bids the on-demand price unless --bid-per-gpu is also set (GPU pods only)" "$l"
}

# A row whose flag+value spans past the description column collapses the gap
# to one space (`--global-networking true|false give the pod …`); the value
# token must still be classified as a value and not swallow the description.
function test_should_classify_long_value_token_rows() {
  local l
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\tglobal-networking\t')"
  assert_equals "0" "$?"
  assert_contains $'value\ttrue|false\tgive the pod a private IP' "$l"
}

# Enum-style value tokens ride the record so the generator can offer them as
# static candidates; bool records carry an empty token field.
function test_should_emit_value_tokens() {
  local l
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\tcloud\t')"
  assert_equals "0" "$?"
  assert_contains $'value\tSECURE|COMMUNITY\t' "$l"
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\tgpu\t')"
  assert_contains $'value\t<type>\t' "$l"
  _spec_has $'f\tpod\tcreate\tssh\tbool\t\t'
}

function test_should_flag_only_options_rows_not_examples_or_usage() {
  # `--pod-count` appears in cluster Examples lines, `--image <ref>` in pod
  # create's Usage line; neither is an Options row.
  local l
  l="$(_spec_line_with_prefix $'f\tcluster\tcreate\tgpu\t')"
  assert_contains "GPU type" "$l" # from the Options row, not the example text
  l="$(_spec_line_with_prefix $'f\tpod\tcreate\timage\t')"
  assert_not_contains "Usage:" "$l"
}

function test_should_emit_global_flag_records_under_star() {
  _spec_has $'f\t*\t*\tjson\tbool'
  _spec_has $'f\t*\t*\tjq\tvalue'
  _spec_has $'f\t*\t*\tinsecure\tbool'
}

# --- usage records ---

function test_should_emit_usage_line_for_verbs_that_document_one() {
  local l
  l="$(_spec_line_with_prefix $'u\tpod\tlogs\t')"
  assert_equals "0" "$?"
  assert_contains "rp pod logs <id>" "$l"
}

# --- coverage invariant ---

# The spec reads doc blocks; a case-arm verb without a `# doc:` block would
# surface in completions with no flags and no description. Every resource's
# verbs must therefore carry a marker block.
function test_should_have_a_doc_block_for_every_case_arm_verb() {
  local file verb block
  for file in "$RP_ROOT"/commands/*.sh; do
    while IFS= read -r verb; do
      [[ -n "$verb" ]] || continue
      block="$(rp::doc_verb_marker "$file" "$verb")"
      assert_not_equals "" "$block"
    done <<<"$(rp::doc_verbs "$file")"
  done
}
