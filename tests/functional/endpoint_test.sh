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
  source "$RP_ROOT/lib/hub.sh"
  source "$RP_ROOT/commands/endpoint.sh"
  eval "$_opts"
}

function test_should_return_existing_id_when_endpoint_name_exists() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[{"id":"ep1","name":"glm-ocr","templateId":"t"}]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"ep1"}'
    fi
  }
  rp::args_parse --name glm-ocr --template t
  out="$(_endpoint_create 2>/dev/null)"
  assert_equals "ep1" "$out"
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_post_when_endpoint_name_is_new() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"newep"}'
    fi
  }
  # --gpu (not --gpus-from-volume) avoids the network-volume/graphql path
  rp::args_parse --name fresh-ep --template t --gpu "NVIDIA L4"
  out="$(_endpoint_create 2>/dev/null)"
  assert_equals "newep" "$out"
  assert_equals "POSTED" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_set_cuda_exec_timeout_and_volume_ids_on_create() {
  local body
  body="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then printf '[]'; else
      printf '%s' "${3:-}" >"$body"
      printf '{"id":"e1"}'
    fi
  }
  rp::args_parse --name e1 --template t --min-cuda-version 12.4 --execution-timeout 300 --network-volume-ids nv1,nv2
  _endpoint_create >/dev/null 2>&1
  assert_equals '"12.4"' "$(jq -c '.minCudaVersion' "$body")"
  assert_equals '300000' "$(jq -r '.executionTimeoutMs' "$body")"
  assert_equals 'nv2' "$(jq -r '.networkVolumeIds[1]' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_warn_when_env_given_with_template() {
  rp::http() {
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{"id":"e1"}'; fi
  }
  rp::args_parse --name e1 --template t --env FOO=bar
  local err
  err="$(_endpoint_create 2>&1 >/dev/null)"
  assert_contains "ignored" "$err"
  rp::http() { :; }
}

function test_should_deploy_via_save_endpoint_when_hub_id_given() {
  local fixture payload
  payload="$(mktemp)"
  fixture="$(jq -c -n --arg img 'vllm:1' --arg cfg '{"gpuIds":"AMPERE_80,ADA_80_PRO","gpuCount":1,"containerDiskInGb":20}' \
    '{listing:{id:"h1",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::http() { [[ "$1" == "GET" ]] && printf '[]'; }
  rp::graphql() {
    if [[ "$1" == *"listing(id"* ]]; then
      printf '%s' "$fixture"
    else
      printf '%s' "$2" >"$payload"
      printf '{"saveEndpoint":{"id":"newhub","name":"glm"}}'
    fi
  }
  rp::args_parse --hub-id h1 --name glm --env MODEL_NAME=glm
  local out
  out="$(_endpoint_create 2>/dev/null)"
  assert_equals "newhub" "$out"
  assert_equals '"h1"' "$(jq -c '.input.hubReleaseId' "$payload")"
  assert_equals '"AMPERE_80,ADA_80_PRO"' "$(jq -c '.input.gpuIds' "$payload")"
  assert_equals 'glm' "$(jq -r '.input.template.env[0].value' "$payload")"
  rp::http() { :; }
  rp::graphql() { :; }
  rm -f "$payload"
}

function test_should_reject_hub_id_with_template() {
  rp::http() { [[ "$1" == "GET" ]] && printf '[]'; }
  rp::args_parse --hub-id h1 --name glm --template t
  (_endpoint_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

function test_should_post_runsync_with_wrapped_input_when_run_given() {
  local cap meta out
  cap="$(mktemp)"
  meta="$(mktemp)"
  rp::http_api() {
    printf '%s %s %s' "$1" "$2" "${4:-}" >"$meta"
    printf '%s' "${3:-}" >"$cap"
    printf '{"status":"COMPLETED","output":{"ok":true}}'
  }
  rp::args_parse e1 --input '{"image":"b64data"}'
  out="$(_endpoint_run 2>/dev/null)"
  assert_equals "POST /e1/runsync 300" "$(<"$meta")"
  assert_equals "b64data" "$(jq -r '.input.image' "$cap")"
  assert_contains '"COMPLETED"' "$out"
  rp::http_api() { :; }
  rm -f "$cap" "$meta"
}

function test_should_post_run_and_print_job_id_when_async_given() {
  local meta out
  meta="$(mktemp)"
  rp::http_api() {
    printf '%s %s %s' "$1" "$2" "${4:-}" >"$meta"
    printf '{"id":"job-42","status":"IN_QUEUE"}'
  }
  rp::args_parse e1 --async --input '{}' --timeout 600
  out="$(_endpoint_run 2>/dev/null)"
  assert_equals "POST /e1/run 600" "$(<"$meta")"
  assert_equals "job-42" "$out"
  rp::http_api() { :; }
  rm -f "$meta"
}

function test_should_read_payload_from_file_when_input_file_given() {
  local cap infile out
  cap="$(mktemp)"
  infile="$(mktemp)"
  printf '{"image":"from-file"}' >"$infile"
  rp::http_api() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"status":"COMPLETED"}'
  }
  rp::args_parse e1 --input-file "$infile"
  out="$(_endpoint_run 2>/dev/null)"
  assert_equals "from-file" "$(jq -r '.input.image' "$cap")"
  assert_contains '"COMPLETED"' "$out"
  rp::http_api() { :; }
  rm -f "$cap" "$infile"
}

function test_should_print_raw_body_when_run_given_json_flag() {
  rp::http_api() { printf '{"status":"COMPLETED","output":{"ok":true}}'; }
  rp::args_parse e1 --input '{}' --json
  local out
  out="$(_endpoint_run 2>/dev/null)"
  assert_equals '{"status":"COMPLETED","output":{"ok":true}}' "$out"
  rp::http_api() { :; }
}

function test_should_exit_usage_when_run_missing_id_or_input() {
  rp::http_api() { :; }
  rp::args_parse --input '{}'
  (_endpoint_run >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse e1
  (_endpoint_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_usage_when_run_given_conflicting_flags() {
  rp::http_api() { :; }
  rp::args_parse e1 --input '{}' --input-file /tmp/x
  (_endpoint_run >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse e1 --input '{}' --sync --async
  (_endpoint_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_usage_when_run_input_is_invalid_json() {
  rp::http_api() { :; }
  rp::args_parse e1 --input 'not-json{'
  (_endpoint_run >/dev/null 2>&1)
  assert_exit_code 2
}

# main-shell dispatcher call so the public rp::cmd_endpoint entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_endpoint help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp endpoint" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_endpoint_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_endpoint list >/dev/null 2>&1
  assert_contains "GET /endpoints" "$(<"$cap")"
  rp::cmd_endpoint get e1 >/dev/null 2>&1
  assert_contains "GET /endpoints/e1" "$(<"$cap")"
  rp::cmd_endpoint create --template t --gpu "NVIDIA L4" >/dev/null 2>&1
  assert_contains "POST /endpoints" "$(<"$cap")"
  rp::cmd_endpoint update e1 --workers-min 1 >/dev/null 2>&1
  assert_contains "PATCH /endpoints/e1" "$(<"$cap")"
  rp::cmd_endpoint scale e1 --min 0 --max 1 >/dev/null 2>&1
  assert_contains "PATCH /endpoints/e1" "$(<"$cap")"
  rp::cmd_endpoint delete e1 >/dev/null 2>&1
  assert_contains "DELETE /endpoints/e1" "$(<"$cap")"
  rp::http_api() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_endpoint run e1 --input '{}' >/dev/null 2>&1
  assert_contains "POST /e1/runsync" "$(<"$cap")"
  rp::http_api() { :; }
  rm -f "$cap"
}
