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
# `rp demo` — a demo command.
# Usage: rp demo <verb> [flags]
#

# doc: create
# Create a demo thing.
# Options:
#   --name <n>   the name
rp::cmd_demo() {
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
  assert_contains '`rp demo` — a demo command.' "$(<"$OUT")"
  assert_contains "Usage: rp demo <verb> [flags]" "$(<"$OUT")"
  [[ "$(<"$OUT")" != *"##DOC"* ]] || return 1
}

function test_intro_summary_is_first_body_line() {
  rp::doc_intro_summary "$FIX" >"$OUT"
  assert_equals '`rp demo` — a demo command.' "$(<"$OUT")"
}

function test_verb_marker_extracts_block() {
  rp::doc_verb_marker "$FIX" create >"$OUT"
  assert_contains "Create a demo thing." "$(<"$OUT")"
  assert_contains "--name <n>   the name" "$(<"$OUT")"
  [[ "$(<"$OUT")" != *"doc: create"* ]] || return 1
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
  [[ "$(<"$OUT")" != *"help"* ]] || return 1
}
