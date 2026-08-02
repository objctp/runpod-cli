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
  OUT="$(mktemp)"
  FIX="$(mktemp)"
  cat >"$FIX" <<'EOF'
#!/usr/bin/env bash
#
# A demo command.
#
# Usage: rp demo <verb> [flags]
#

# doc: create
# Create a demo thing.
#
# Usage: rp demo create --name <n>
#
# Options:
#   --name <n>   the name
#
# API: POST /v2/demos
# doc: grants add
# Add a grant to a demo thing.
#
# Usage: rp demo grants add <id>

rp::cmd_demo() {
  if [[ "$verb" == "grants" ]]; then
    case "$sub" in
    add) _demo_grants_add ;;
    drop) _demo_grants_drop ;;
    -h | --help | help) : ;;
    esac
    return
  fi
  case "$verb" in
  create) _demo_create ;;
  list) _demo_list ;;
  help) : ;;
  esac
}

# Make a demo.
# Arguments:
#   $1 - x: the thing
# Returns:
#   0 - ok
_demo_create() {
  :
}
EOF
}

function tear_down() {
  rm -f "$OUT" "$FIX"
}

function test_intro_prints_body_without_markers() {
  rp::doc_intro "$FIX" >"$OUT"
  assert_contains 'A demo command.' "$(<"$OUT")"
  assert_contains "Usage: rp demo <verb> [flags]" "$(<"$OUT")"
  assert_not_contains "##DOC" "$(<"$OUT")"
}

function test_intro_summary_is_first_body_line() {
  rp::doc_intro_summary "$FIX" >"$OUT"
  assert_equals 'A demo command.' "$(<"$OUT")"
}

function test_verb_marker_extracts_block() {
  rp::doc_verb_marker "$FIX" create >"$OUT"
  assert_contains "Create a demo thing." "$(<"$OUT")"
  assert_contains "--name <n>   the name" "$(<"$OUT")"
  assert_not_contains "doc: create" "$(<"$OUT")"
}

# A bare `#` line is a paragraph break inside a block, not a terminator: only a
# truly blank line (or the next marker) ends one.
function test_verb_marker_keeps_internal_blank_lines() {
  rp::doc_verb_marker "$FIX" create >"$OUT"
  assert_contains "$(printf 'Create a demo thing.\n\nUsage:')" "$(<"$OUT")"
}

# The block runs up to the next `# doc:` marker, and must not absorb it.
function test_verb_marker_stops_at_next_marker() {
  rp::doc_verb_marker "$FIX" create >"$OUT"
  assert_not_contains "Add a grant" "$(<"$OUT")"
  assert_equals "API: POST /v2/demos" "$(tail -n1 "$OUT")"
}

function test_verb_marker_accepts_space_separated_subverb_name() {
  rp::doc_verb_marker "$FIX" "grants add" >"$OUT"
  assert_contains "Add a grant to a demo thing." "$(<"$OUT")"
}

function test_verb_marker_is_empty_for_unknown_verb() {
  rp::doc_verb_marker "$FIX" nope >"$OUT"
  assert_empty "$(<"$OUT")"
}

function test_func_doc_fallback_extracts_handler_comment() {
  rp::doc_func_doc "$FIX" _demo_create >"$OUT"
  assert_contains "Make a demo." "$(<"$OUT")"
  assert_contains '$1 - x: the thing' "$(<"$OUT")"
}

function test_verbs_lists_case_labels_not_help() {
  rp::doc_verbs "$FIX" >"$OUT"
  assert_contains "create" "$(<"$OUT")"
  assert_contains "list" "$(<"$OUT")"
  assert_not_contains "help" "$(<"$OUT")"
}

# A group verb is dispatched by an `if [[ "$verb" == … ]]` guard, not a case
# arm, so it needs discovering separately or `rp doc` cannot reach it.
function test_verbs_includes_group_verb() {
  rp::doc_verbs "$FIX" >"$OUT"
  assert_contains "grants" "$(<"$OUT")"
}

function test_subverbs_lists_sub_case_labels() {
  rp::doc_subverbs "$FIX" grants >"$OUT"
  assert_contains "add" "$(<"$OUT")"
  assert_contains "drop" "$(<"$OUT")"
  assert_not_contains "help" "$(<"$OUT")"
}

# The outer case must not leak into a group's sub-verbs.
function test_subverbs_excludes_outer_case_labels() {
  rp::doc_subverbs "$FIX" grants >"$OUT"
  assert_not_contains "create" "$(<"$OUT")"
}

function test_subverbs_empty_for_non_group_verb() {
  rp::doc_subverbs "$FIX" create >"$OUT"
  assert_empty "$(<"$OUT")"
}
