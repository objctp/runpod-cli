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
  source "$RP_ROOT/lib/hub.sh"
  source "$RP_ROOT/commands/serverless.sh"
  eval "$_opts"
}

function set_up() {
  # GPU-pool lookups are cached for the process lifetime; reset between tests.
  _RP_GPU_POOLS=''
}

function test_should_return_existing_id_when_endpoint_name_exists() {
  local marker out err
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '{"endpoints":[{"id":"ep1","name":"glm-ocr"}]}'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"ep1"}'
    fi
  }
  # No --gpu: the idempotency gate must win over the v2 GPU requirement.
  rp::args_parse --name glm-ocr --template t
  out="$(_serverless_create 2>/dev/null)"
  assert_equals "ep1" "$out"
  assert_equals "" "$(cat "$marker")"
  err="$(_serverless_create 2>&1 >/dev/null)"
  assert_contains "serverless 'glm-ocr' exists: ep1" "$err"
  rp::http() { :; }
  rm -f "$marker"
}

# --template stays required even on an idempotent hit (same convention as
# volume/template create): idempotency covers re-runs, not bare-name lookups.
function test_should_require_template_even_when_name_exists() {
  rp::http() { printf '{"endpoints":[{"id":"ep1","name":"glm-ocr"}]}'; }
  rp::args_parse --name glm-ocr
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

# v2-shaped mock for the create path: endpoint lookup, template fetch, GPU
# catalogue (pool mapping), and the final POST /serverless. Captures go to the
# MOCK_MARKER / MOCK_BODY files when set.
function _mock_create_http() {
  MOCK_MARKER="$1"
  MOCK_BODY="${2:-}"
  MOCK_TEMPLATE="${3:-}"
  [[ -n "$MOCK_TEMPLATE" ]] || MOCK_TEMPLATE='{"id":"t","image":"img:1","disk":10}'
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'GET /templates/t') printf '%s' "$MOCK_TEMPLATE" ;;
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"}]}' ;;
    'POST /serverless')
      printf 'POSTED' >>"$MOCK_MARKER"
      [[ -n "$MOCK_BODY" ]] && printf '%s' "${3:-}" >"$MOCK_BODY"
      printf '{"id":"newep"}'
      ;;
    esac
  }
}

function test_should_post_when_endpoint_name_is_new() {
  local marker out
  marker="$(mktemp)"
  _mock_create_http "$marker"
  # --gpu (not --gpus-from-volume) avoids the network-volume path
  rp::args_parse --name fresh-ep --template t --gpu "NVIDIA L4"
  out="$(_serverless_create 2>/dev/null)"
  assert_equals "newep" "$out"
  assert_equals "POSTED" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_spread_template_and_map_gpu_pool_on_create() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --workers-min 1 --workers-max 3 --idle 10
  _serverless_create >/dev/null 2>&1
  assert_equals 'img:1' "$(jq -r '.image' "$body")"
  assert_equals 'ADA_24' "$(jq -r '.gpu.pools[0]' "$body")"
  assert_equals 'QUEUE' "$(jq -r '.type' "$body")"
  assert_equals 'QUEUE_DELAY' "$(jq -r '.scaling.type' "$body")"
  assert_equals '4' "$(jq -r '.scaling.queueDelay' "$body")"
  assert_equals '1' "$(jq -r '.workers.min' "$body")"
  assert_equals '3' "$(jq -r '.workers.max' "$body")"
  assert_equals '10' "$(jq -r '.workers.idleTimeout' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

function test_should_set_exec_timeout_volume_ids_and_flashboot_on_create() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --execution-timeout 300 --network-volume-ids nv1,nv2 --flashboot
  _serverless_create >/dev/null 2>&1
  assert_equals '300000' "$(jq -r '.timeout' "$body")"
  assert_equals 'nv2' "$(jq -r '.networkVolumes[1]' "$body")"
  assert_equals 'FLASHBOOT' "$(jq -r '.flashboot' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

# v2 CreateEndpointRequest has no minCudaVersion (unevaluatedProperties: false
# would reject the whole create); the flag must be dropped with a warning.
function test_should_ignore_min_cuda_version_on_create() {
  local marker body err
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --min-cuda-version 12.4
  err="$(_serverless_create 2>&1 >/dev/null)"
  assert_equals 'null' "$(jq -c '.minCudaVersion' "$body")"
  assert_contains "ignored" "$err"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

# --env must overlay the template's env (user wins per key), not be dropped.
function test_should_merge_env_over_template_env_on_create() {
  local marker body err
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body" '{"id":"t","image":"img:1","disk":10,"env":{"KEEP":"1","OVERRIDE":"template"}}'
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --env OVERRIDE=user --env NEW=2
  err="$(_serverless_create 2>&1 >/dev/null)"
  assert_equals '1' "$(jq -r '.env.KEEP' "$body")"
  assert_equals 'user' "$(jq -r '.env.OVERRIDE' "$body")"
  assert_equals '2' "$(jq -r '.env.NEW' "$body")"
  assert_not_contains "ignored" "$err"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

function test_should_override_template_registry_when_create_flag_given() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body" '{"id":"t","image":"img:1","disk":10,"registry":"reg-template"}'
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --registry reg-123
  _serverless_create >/dev/null 2>&1
  assert_equals 'reg-123' "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

function test_should_omit_registry_when_create_flag_absent() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body" '{"id":"t","image":"img:1","disk":10,"registry":"reg-template"}'
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4"
  _serverless_create >/dev/null 2>&1
  assert_equals 'reg-template' "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

function test_should_set_registry_on_hub_path() {
  local fixture payload
  payload="$(mktemp)"
  fixture="$(jq -c -n --arg img 'vllm:1' --arg cfg '{"gpuIds":"ADA_80_PRO","gpuCount":1,"containerDiskInGb":20}' \
    '{listing:{id:"h1",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'POST /serverless')
      printf '%s' "${3:-}" >"$payload"
      printf '{"id":"newhub","name":"glm"}'
      ;;
    esac
  }
  rp::graphql() { printf '%s' "$fixture"; }
  rp::args_parse --hub-id h1 --name glm --registry reg-789
  _serverless_create >/dev/null 2>&1
  assert_equals 'reg-789' "$(jq -r '.registry' "$payload")"
  rp::http() { :; }
  rp::graphql() { :; }
  rm -f "$payload"
}

function test_should_set_registry_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --registry reg-upd
  _serverless_update >/dev/null 2>&1
  assert_equals 'reg-upd' "$(jq -r '.registry' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

function test_should_exit_usage_when_create_has_no_gpu() {
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'GET /templates/t') printf '{"id":"t","image":"img:1"}' ;;
    esac
  }
  rp::args_parse --name e1 --template t
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

function test_should_deploy_via_rest_when_hub_id_given() {
  local fixture payload
  payload="$(mktemp)"
  fixture="$(jq -c -n --arg img 'vllm:1' --arg cfg '{"gpuIds":"AMPERE_80,ADA_80_PRO","gpuCount":1,"containerDiskInGb":20}' \
    '{listing:{id:"h1",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'POST /serverless')
      printf '%s' "${3:-}" >"$payload"
      printf '{"id":"newhub","name":"glm"}'
      ;;
    esac
  }
  rp::graphql() { printf '%s' "$fixture"; }
  rp::args_parse --hub-id h1 --name glm --env MODEL_NAME=glm
  local out
  out="$(_serverless_create 2>/dev/null)"
  assert_equals "newhub" "$out"
  assert_equals 'vllm:1' "$(jq -r '.image' "$payload")"
  assert_equals 'AMPERE_80' "$(jq -r '.gpu.pools[0]' "$payload")"
  assert_equals 'ADA_80_PRO' "$(jq -r '.gpu.pools[1]' "$payload")"
  assert_equals '20' "$(jq -r '.disk' "$payload")"
  assert_equals 'glm' "$(jq -r '.env.MODEL_NAME' "$payload")"
  assert_equals 'QUEUE' "$(jq -r '.type' "$payload")"
  assert_equals 'QUEUE_DELAY' "$(jq -r '.scaling.type' "$payload")"
  assert_equals '4' "$(jq -r '.scaling.queueDelay' "$payload")"
  rp::http() { :; }
  rp::graphql() { :; }
  rm -f "$payload"
}

function test_should_reject_hub_id_with_template() {
  rp::http() { [[ "$1" == "GET" ]] && printf '[]'; }
  rp::args_parse --hub-id h1 --name glm --template t
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

# Live spec: type LOAD_BALANCER requires REQUEST_COUNT scaling; a queue-delay
# scaler must be rejected locally before any HTTP call.
function test_should_error_when_load_balancer_with_queue_delay_scaler() {
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'GET /templates/t') printf '{"id":"t","image":"img:1"}' ;;
    esac
  }
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --type LOAD_BALANCER --scaler-type QUEUE_DELAY
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

# LOAD_BALANCER with the default (REQUEST_COUNT) scaling is accepted and sends the
# correct union arm.
function test_should_default_request_count_scaling_for_load_balancer() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --type LOAD_BALANCER
  _serverless_create >/dev/null 2>&1
  assert_equals 'LOAD_BALANCER' "$(jq -r '.type' "$body")"
  assert_equals 'REQUEST_COUNT' "$(jq -r '.scaling.type' "$body")"
  assert_equals '1' "$(jq -r '.scaling.requestCount' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

# workers.idleTimeout is rejected for REQUEST_COUNT scaling; --idle must be
# dropped with a warning rather than sent.
function test_should_drop_idle_when_request_count_scaling() {
  local marker body err
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --scaler-type REQUEST_COUNT --scaler-value 2 --idle 10
  err="$(_serverless_create 2>&1 >/dev/null)"
  assert_equals 'null' "$(jq -c '.workers.idleTimeout' "$body")"
  assert_equals 'REQUEST_COUNT' "$(jq -r '.scaling.type' "$body")"
  assert_equals '2' "$(jq -r '.scaling.requestCount' "$body")"
  assert_contains "ignored" "$err"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

# rp serverless list reads idleTimeout from workers (not scaling) post-fix. The
# reshape only runs in the human-table path (--json emits the raw array).
function test_should_reshape_list_idle_timeout_from_workers() {
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[{"id":"e1","name":"glm","workers":{"min":0,"max":3,"idleTimeout":7}}]}' ;;
    *) printf '[]' ;;
    esac
  }
  local out
  out="$(rp::cmd_serverless list 2>/dev/null)"
  assert_contains "idleTimeout" "$out"
  assert_contains "7" "$out"
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
  out="$(_serverless_run 2>/dev/null)"
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
  out="$(_serverless_run 2>/dev/null)"
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
  out="$(_serverless_run 2>/dev/null)"
  assert_equals "from-file" "$(jq -r '.input.image' "$cap")"
  assert_contains '"COMPLETED"' "$out"
  rp::http_api() { :; }
  rm -f "$cap" "$infile"
}

function test_should_print_raw_body_when_run_given_json_flag() {
  rp::http_api() { printf '{"status":"COMPLETED","output":{"ok":true}}'; }
  rp::args_parse e1 --input '{}' --json
  local out
  out="$(_serverless_run 2>/dev/null)"
  assert_equals '{"status":"COMPLETED","output":{"ok":true}}' "$out"
  rp::http_api() { :; }
}

function test_should_exit_usage_when_run_missing_id_or_input() {
  rp::http_api() { :; }
  rp::args_parse --input '{}'
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse e1
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_usage_when_run_given_conflicting_flags() {
  rp::http_api() { :; }
  rp::args_parse e1 --input '{}' --input-file /tmp/x
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
  rp::args_parse e1 --input '{}' --sync --async
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_usage_when_run_input_is_invalid_json() {
  rp::http_api() { :; }
  rp::args_parse e1 --input 'not-json{'
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

# rp::api_stream recording double: captures "<plane> <path> <leid>" into $cap.
function test_should_route_serverless_logs_to_stream() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_serverless logs e1 --worker w1 >/dev/null 2>&1
  assert_equals "rest /serverless/e1/workers/w1/logs " "$(<"$cap")"
  rm -f "$cap"
}

function test_should_require_worker_in_serverless_logs() {
  rp::api_stream() { :; }
  (rp::cmd_serverless logs e1 >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_compose_serverless_logs_flags_onto_query() {
  local cap
  cap="$(mktemp)"
  rp::api_stream() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >"$cap"; }
  rp::cmd_serverless logs e1 --worker w1 --source system --tail 0 >/dev/null 2>&1
  assert_equals "rest /serverless/e1/workers/w1/logs?source=system&tail=0 " "$(<"$cap")"
  rm -f "$cap"
}

# main-shell dispatcher call so the public rp::cmd_serverless entry registers coverage.
function test_should_show_help_when_help_verb_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_serverless help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp serverless" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each verb branch registers.
function test_should_route_each_serverless_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    case "$1 $2" in
    'GET /templates/t') printf '{"id":"t","image":"img:1"}' ;;
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"}]}' ;;
    GET*) printf '[]' ;;
    *) printf '{"id":"e1"}' ;;
    esac
  }
  rp::cmd_serverless list >/dev/null 2>&1
  assert_contains "GET /serverless" "$(<"$cap")"
  rp::cmd_serverless get e1 >/dev/null 2>&1
  assert_contains "GET /serverless/e1" "$(<"$cap")"
  rp::cmd_serverless create --template t --gpu "NVIDIA L4" >/dev/null 2>&1
  assert_contains "POST /serverless" "$(<"$cap")"
  rp::cmd_serverless update e1 --workers-min 1 >/dev/null 2>&1
  assert_contains "PATCH /serverless/e1" "$(<"$cap")"
  rp::cmd_serverless scale e1 --min 0 --max 1 >/dev/null 2>&1
  assert_contains "PATCH /serverless/e1" "$(<"$cap")"
  rp::cmd_serverless delete e1 >/dev/null 2>&1
  assert_contains "DELETE /serverless/e1" "$(<"$cap")"
  rp::http_api() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{}'
  }
  rp::cmd_serverless run e1 --input '{}' >/dev/null 2>&1
  assert_contains "POST /e1/runsync" "$(<"$cap")"
  rp::http_api() { :; }
  rm -f "$cap"
}

# The deprecated `endpoint` resource name still routes through the renamed
# command module, warning on stderr.
function test_should_route_deprecated_endpoint_resource_with_warning() {
  local cap err
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '[]'
  }
  . "$RP_ROOT/commands/endpoint.sh"
  err="$(rp::cmd_endpoint list 2>&1 >/dev/null)"
  assert_contains "deprecated" "$err"
  assert_contains "GET /serverless" "$(<"$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

# rp serverless workers e1 — human path tables active workers and prints the
# status histogram on stderr.
function test_should_table_workers_and_histogram_on_workers() {
  rp::http() {
    printf '{"endpointVersion":4,"summary":{"running":1,"idle":1,"initializing":0,"throttled":0,"unhealthy":0,"total":2},"workers":[{"id":"w1","status":"RUNNING","gpuCount":1,"isStale":false,"version":4,"image":"img:1","uptimeSeconds":3600,"gpuTypeId":"NVIDIA 4090","dataCenterId":"US-KS-2"}]}'
  }
  local out err
  out="$(rp::cmd_serverless workers e1 2>/tmp/w_err)"
  err="$(cat /tmp/w_err)"
  assert_contains "id" "$out"
  assert_contains "status" "$out"
  assert_contains "gpuType" "$out"
  assert_contains "dc" "$out"
  assert_contains "RUNNING" "$out"
  assert_contains "w1" "$out"
  assert_contains "total=2" "$err"
  assert_contains "running=1" "$err"
  rp::http() { :; }
  rm -f /tmp/w_err
}

# rp serverless workers e1 --json — emits the raw envelope verbatim, no headline.
function test_should_emit_raw_envelope_on_workers_json() {
  local envelope='{"endpointVersion":4,"summary":{"running":1,"idle":1,"initializing":0,"throttled":0,"unhealthy":0,"total":2},"workers":[{"id":"w1","status":"RUNNING"}]}'
  rp::http() { printf '%s' "$envelope"; }
  local out err
  out="$(rp::cmd_serverless workers e1 --json 2>/tmp/w_err)"
  err="$(cat /tmp/w_err)"
  assert_equals "$envelope" "$out"
  assert_equals "" "$err"
  rp::http() { :; }
  rm -f /tmp/w_err
}

# An endpoint with no active workers prints the header row and a total=0 headline.
function test_should_render_empty_workers_cleanly() {
  rp::http() { printf '{"endpointVersion":4,"summary":{"running":0,"idle":0,"initializing":0,"throttled":0,"unhealthy":0,"total":0},"workers":[]}'; }
  local out err
  out="$(rp::cmd_serverless workers e1 2>/tmp/w_err)"
  err="$(cat /tmp/w_err)"
  assert_contains "id" "$out"
  assert_not_contains "RUNNING" "$out"
  assert_contains "total=0" "$err"
  rp::http() { :; }
  rm -f /tmp/w_err
}

# rp serverless workers with no id exits usage (code 2).
function test_should_exit_usage_when_workers_missing_id() {
  rp::http() { :; }
  (rp::cmd_serverless workers >/dev/null 2>&1)
  assert_exit_code 2
}

# rp serverless releases e1 — human path tables releases with a compact diff and
# prints the rollout summary on stderr.
function test_should_table_releases_and_rollout_on_releases() {
  rp::http() {
    printf '{"endpointVersion":4,"rollout":{"inProgress":true,"workersOnLatest":1,"workersTotal":2,"percentOnLatest":50},"releases":[{"id":"r1","source":"MANUAL","createdAt":"2026-06-01T12:10:00Z","workerCount":2,"diff":[{"field":"workers.max","old":5,"new":10}],"version":4,"buildId":null}]}'
  }
  local out err
  out="$(rp::cmd_serverless releases e1 2>/tmp/r_err)"
  err="$(cat /tmp/r_err)"
  assert_contains "MANUAL" "$out"
  assert_contains "2026-06-01T12:10:00Z" "$out"
  assert_contains "workers.max: 5 → 10" "$out"
  assert_contains "1/2 on latest" "$err"
  assert_contains "in progress" "$err"
  rp::http() { :; }
  rm -f /tmp/r_err
}

# rp serverless releases e1 --json — emits the raw envelope verbatim (incl. rollout).
function test_should_emit_raw_envelope_on_releases_json() {
  local envelope='{"endpointVersion":4,"rollout":{"inProgress":false,"workersOnLatest":2,"workersTotal":2,"percentOnLatest":100},"releases":[{"id":"r1","source":"MANUAL","createdAt":"2026-06-01T12:10:00Z","workerCount":2,"diff":[],"version":4,"buildId":null}]}'
  rp::http() { printf '%s' "$envelope"; }
  local out err
  out="$(rp::cmd_serverless releases e1 --json 2>/tmp/r_err)"
  err="$(cat /tmp/r_err)"
  assert_equals "$envelope" "$out"
  assert_equals "" "$err"
  rp::http() { :; }
  rm -f /tmp/r_err
}

# Route workers/releases through the public dispatcher to the right GET paths.
function test_should_route_workers_and_releases_verbs() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"workers":[],"releases":[]}'
  }
  rp::cmd_serverless workers e1 >/dev/null 2>&1
  assert_contains "GET /serverless/e1/workers" "$(<"$cap")"
  rp::cmd_serverless releases e1 >/dev/null 2>&1
  assert_contains "GET /serverless/e1/releases" "$(<"$cap")"
  rp::http() { :; }
  rm -f "$cap"
}
