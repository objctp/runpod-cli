#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/validate.sh"
  source "$RP_ROOT/lib/lookup.sh"
  source "$RP_ROOT/commands/template.sh"
  eval "$_opts"
}

function test_should_return_existing_id_when_template_name_exists() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[{"id":"tpl1","name":"glm-ocr","imageName":"img"}]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"tpl1"}'
    fi
  }
  rp::args_parse --name glm-ocr --image img --serverless
  out="$(_template_create 2>/dev/null)"
  assert_equals "tpl1" "$out"
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_post_when_template_name_is_new() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"newtpl"}'
    fi
  }
  rp::args_parse --name fresh-ocr --image img
  out="$(_template_create 2>/dev/null)"
  assert_equals "newtpl" "$out"
  assert_equals "POSTED" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_omit_volumeInGb_when_serverless_and_volume_gb_given() {
  local body
  body="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$body"
      printf '{"id":"x"}'
    fi
  }
  rp::args_parse --name s-ocr --image img --serverless --volume-gb 20
  _template_create >/dev/null 2>&1
  assert_not_contains "volumeInGb" "$(cat "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_include_volumeInGb_when_not_serverless() {
  local body
  body="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$body"
      printf '{"id":"x"}'
    fi
  }
  rp::args_parse --name p-ocr --image img --volume-gb 20
  _template_create >/dev/null 2>&1
  assert_contains "volumeInGb" "$(cat "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_filter_templates_by_name_substring() {
  rp::http() {
    printf '[{"id":"t1","name":"glm-ocr","imageName":"img1","isServerless":true},{"id":"t2","name":"flash-ocr","imageName":"img2","isServerless":false}]'
  }
  rp::args_parse glm
  local out
  out="$(_template_search 2>/dev/null)"
  assert_contains "glm-ocr" "$out"
  assert_not_contains "flash-ocr" "$out"
  rp::http() { :; }
}

function test_should_die_when_template_search_has_no_needle() {
  rp::http() { :; }
  rp::args_parse
  (_template_search >/dev/null 2>&1)
  assert_exit_code 2
}

# main-shell dispatcher call so the public rp::cmd_template entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_template help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp template" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_template_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{}'; fi
  }
  rp::cmd_template list >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$cap")"
  rp::cmd_template get t1 >/dev/null 2>&1
  assert_contains "GET /templates/t1" "$(<"$cap")"
  rp::cmd_template create --name n --image img >/dev/null 2>&1
  assert_contains "POST /templates" "$(<"$cap")"
  rp::cmd_template search glm >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$cap")"
  rp::cmd_template delete t1 >/dev/null 2>&1
  assert_contains "DELETE /templates/t1" "$(<"$cap")"
  rm -f "$cap"
}
