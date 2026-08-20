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
  source "$RP_ROOT/lib/resource.sh"
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
  assert_not_contains "persistent" "$(cat "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_include_volume_mount_path_when_volume_gb_given() {
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
  rp::args_parse --name p-ocr --image img --volume-gb 10 --volume-mount-path /data
  _template_create >/dev/null 2>&1
  assert_equals "10" "$(jq -r '.mounts.persistent.size' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_accept_volume_path_alias_for_mount_path() {
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
  rp::args_parse --name p-ocr --image img --volume-gb 10 --volume-path /data
  _template_create >/dev/null 2>&1
  assert_equals "10" "$(jq -r '.mounts.persistent.size' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_when_volume_mount_path_given_without_volume_gb() {
  rp::http() { :; }
  rp::args_parse --name n --image i --volume-mount-path /data
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
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
  assert_equals "20" "$(jq -r '.mounts.persistent.size' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_send_public_and_registry_when_creating() {
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
  rp::args_parse --name pub-tpl --image img --public true --registry cred1
  _template_create >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.public' "$body")"
  assert_equals "cred1" "$(jq -r '.registry' "$body")"
  rp::args_parse --name plain-tpl --image img
  _template_create >/dev/null 2>&1
  assert_equals "null" "$(jq -r '.public' "$body")"
  assert_equals "null" "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_patch_template_fields_on_update() {
  local cap body
  cap="$(mktemp)"
  body="$(mktemp)"
  rp::http() {
    printf '%s %s' "$1" "$2" >"$cap"
    printf '%s' "$3" >"$body"
    printf '{"id":"t1"}'
  }
  rp::args_parse t1 --registry cred1 --name renamed --docker-cmd a,b --public false
  _template_update >/dev/null 2>&1
  assert_equals "PATCH /templates/t1" "$(<"$cap")"
  assert_equals "cred1" "$(jq -r '.registry' "$body")"
  assert_equals "renamed" "$(jq -r '.name' "$body")"
  assert_equals "a b" "$(jq -r '.args' "$body")"
  assert_equals "false" "$(jq -r '.public' "$body")"
  rp::args_parse t1 --public true
  _template_update >/dev/null 2>&1
  assert_equals "true" "$(jq -r '.public' "$body")"
  rp::http() { :; }
  rm -f "$cap" "$body"
}

function test_should_include_volume_mount_path_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "$3" >"$body"
    printf '{"id":"t1"}'
  }
  rp::args_parse t1 --volume-gb 10 --volume-mount-path /data
  _template_update >/dev/null 2>&1
  assert_equals "10" "$(jq -r '.mounts.persistent.size' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_accept_volume_path_alias_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "$3" >"$body"
    printf '{"id":"t1"}'
  }
  rp::args_parse t1 --volume-gb 10 --volume-path /data
  _template_update >/dev/null 2>&1
  assert_equals "10" "$(jq -r '.mounts.persistent.size' "$body")"
  assert_equals "/data" "$(jq -r '.mounts.persistent.path' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_die_on_update_when_volume_mount_path_without_volume_gb() {
  rp::http() { :; }
  rp::args_parse t1 --volume-mount-path /data
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_update_has_no_fields() {
  rp::http() { :; }
  rp::args_parse t1
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_update_public_is_not_boolean() {
  rp::http() { :; }
  rp::args_parse t1 --public maybe
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_update_has_no_id() {
  rp::http() { :; }
  rp::args_parse --name n
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_die_when_category_outside_enum() {
  rp::http() { :; }
  rp::args_parse --name n --image i --category BOGUS
  (_template_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse t1 --category GPU
  (_template_update >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_accept_valid_category_enum_on_create() {
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
  rp::args_parse --name n --image i --category AMD
  _template_create >/dev/null 2>&1
  assert_equals "AMD" "$(jq -r '.category' "$body")"
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
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{"id":"t1"}'; fi
  }
  rp::cmd_template list >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$cap")"
  rp::cmd_template get t1 >/dev/null 2>&1
  assert_contains "GET /templates/t1" "$(<"$cap")"
  rp::cmd_template create --name n --image img >/dev/null 2>&1
  assert_contains "POST /templates" "$(<"$cap")"
  rp::cmd_template update t1 --name renamed >/dev/null 2>&1
  assert_contains "PATCH /templates/t1" "$(<"$cap")"
  rp::cmd_template search glm >/dev/null 2>&1
  assert_contains "GET /templates" "$(<"$cap")"
  rp::cmd_template delete t1 >/dev/null 2>&1
  assert_contains "DELETE /templates/t1" "$(<"$cap")"
  rm -f "$cap"
}
