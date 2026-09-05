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

# --name is required on the --template path too (mirrors the --hub-id path); a
# bare --template with no --name must die locally, not reach the API.
function test_should_die_when_create_missing_name_on_template_path() {
  rp::http() { :; }
  rp::args_parse --template t
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

function test_create_accepts_template_id_and_passes_native_field() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template-id tpl_nat --gpu "NVIDIA L4"
  _serverless_create >/dev/null 2>&1
  assert_equals "tpl_nat" "$(jq -r '.templateId' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

function test_create_requires_template_or_template_id() {
  rp::http() { :; }
  rp::args_parse --name e1 --gpu "NVIDIA L4"
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

function test_create_template_id_wins_over_template_spread() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  # Both given: --template-id must win, so the body carries templateId and the
  # template is NOT spread (no .image from the template fetch).
  rp::args_parse --name e1 --template t --template-id tpl_nat --gpu "NVIDIA L4"
  _serverless_create >/dev/null 2>&1
  assert_equals "tpl_nat" "$(jq -r '.templateId' "$body")"
  assert_equals "false" "$(jq -r 'has("image")' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
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

# --exclude-gpu subtracts GPU type ids from the selected pools (gpu.excludedTypes).
function test_should_send_excluded_types_on_create() {
  local marker body
  marker="$(mktemp)"
  body="$(mktemp)"
  _mock_create_http "$marker" "$body"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --exclude-gpu "NVIDIA L4"
  _serverless_create >/dev/null 2>&1
  assert_equals 'ADA_24' "$(jq -r '.gpu.pools[0]' "$body")"
  assert_equals '["NVIDIA L4"]' "$(jq -c '.gpu.excludedTypes' "$body")"
  rp::http() { :; }
  rm -f "$marker" "$body"
}

# Validation is client-side: an exclusion outside the selected pools would
# silently exclude nothing at the API, so it must die locally, before any POST.
function test_should_reject_excluded_type_outside_selected_pools_on_create() {
  local marker
  marker="$(mktemp)"
  _mock_create_http "$marker"
  rp::args_parse --name e1 --template t --gpu "NVIDIA L4" --exclude-gpu "NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
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

# --template-id on update swaps the endpoint's template: PATCH body carries
# templateId, and nothing else is forced in when only the template changes.
function test_should_emit_template_id_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --template-id tpl_new
  _serverless_update >/dev/null 2>&1
  assert_equals 'tpl_new' "$(jq -r '.templateId' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# --name on update renames the endpoint: PATCH body carries name.
function test_should_emit_name_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --name renamed-ep
  _serverless_update >/dev/null 2>&1
  assert_equals 'renamed-ep' "$(jq -r '.name' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# --scale-by delay coerces to scaling.type QUEUE_DELAY, and --scale-threshold N
# lands in scaling.queueDelay. These are the runpodctl aliases for rp's own
# --scaler-type/--scaler-value, handled in-command.
function test_should_coerce_scale_by_delay_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --scale-by delay --scale-threshold 30
  _serverless_update >/dev/null 2>&1
  assert_equals 'QUEUE_DELAY' "$(jq -r '.scaling.type' "$body")"
  assert_equals '30' "$(jq -r '.scaling.queueDelay' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# --scale-by requests coerces to scaling.type REQUEST_COUNT, and --scale-threshold
# N lands in scaling.requestCount.
function test_should_coerce_scale_by_requests_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --scale-by requests --scale-threshold 30
  _serverless_update >/dev/null 2>&1
  assert_equals 'REQUEST_COUNT' "$(jq -r '.scaling.type' "$body")"
  assert_equals '30' "$(jq -r '.scaling.requestCount' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# rp's own --scaler-type/--scaler-value must keep working on update, untouched
# by the new coercion aliases (acceptance: existing flags unaffected).
function test_should_keep_scaler_type_value_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --scaler-type REQUEST_COUNT --scaler-value 5
  _serverless_update >/dev/null 2>&1
  assert_equals 'REQUEST_COUNT' "$(jq -r '.scaling.type' "$body")"
  assert_equals '5' "$(jq -r '.scaling.requestCount' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# rp's native --scaler-type must win when given alongside the --scale-by alias
# (per D1's collision policy: rp's meaning always wins). --scale-by is ignored
# rather than silently flipping the type.
function test_should_let_native_scaler_type_win_over_scale_by() {
  local body
  body="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body"
    printf '{"id":"e1"}'
  }
  rp::args_parse e1 --scaler-type REQUEST_COUNT --scale-by delay
  _serverless_update >/dev/null 2>&1
  assert_equals 'REQUEST_COUNT' "$(jq -r '.scaling.type' "$body")"
  assert_equals '1' "$(jq -r '.scaling.requestCount' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# A PATCH sending pools without excludedTypes CLEARS the exclusions (the API
# replaces the gpu object wholesale), so --exclude-gpu needs --gpu on update.
function test_should_reject_exclude_gpu_without_gpu_on_update() {
  rp::http() { printf '{"id":"e1"}'; }
  rp::args_parse e1 --exclude-gpu "NVIDIA L4"
  (_serverless_update >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
}

# Resending pools alone is a silent exclusion wipe at the API; the CLI says so.
function test_should_warn_when_update_resends_pools_without_exclusions() {
  local body err
  body="$(mktemp)"
  rp::http() {
    case "$1 $2" in
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"}]}' ;;
    *)
      printf '%s' "${3:-}" >"$body"
      printf '{"id":"e1"}'
      ;;
    esac
  }
  rp::args_parse e1 --gpu "NVIDIA L4"
  err="$(_serverless_update 2>&1 >/dev/null)"
  assert_contains "clears any existing gpu.excludedTypes" "$err"
  assert_equals "false" "$(jq -r '.gpu | has("excludedTypes")' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# --gpu + --exclude-gpu on update sends both in one PATCH (exclusions require
# pools in the same PATCH per the API's dependentRequired).
function test_should_send_pools_and_excluded_types_on_update() {
  local body
  body="$(mktemp)"
  rp::http() {
    case "$1 $2" in
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"},{"id":"NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb","pool":"ADA_24"}]}' ;;
    *)
      printf '%s' "${3:-}" >"$body"
      printf '{"id":"e1"}'
      ;;
    esac
  }
  rp::args_parse e1 --gpu "NVIDIA L4" --exclude-gpu "NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"
  _serverless_update >/dev/null 2>&1
  assert_equals 'ADA_24' "$(jq -r '.gpu.pools[0]' "$body")"
  assert_equals '["NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"]' "$(jq -c '.gpu.excludedTypes' "$body")"
  rp::http() { :; }
  rm -f "$body"
}

# --exclude-gpu works on the --hub-id path too: the listing's gpuIds are already
# pool ids, so the same validation applies before the POST body is assembled.
function test_should_send_excluded_types_on_hub_path() {
  local fixture payload
  payload="$(mktemp)"
  fixture="$(jq -c -n --arg img 'vllm:1' --arg cfg '{"gpuIds":"ADA_24","gpuCount":1,"containerDiskInGb":20}' \
    '{listing:{id:"h1",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"},{"id":"NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb","pool":"ADA_24"}]}' ;;
    'POST /serverless')
      printf '%s' "${3:-}" >"$payload"
      printf '{"id":"newhub","name":"glm"}'
      ;;
    esac
  }
  rp::graphql() { printf '%s' "$fixture"; }
  rp::args_parse --hub-id h1 --name glm --exclude-gpu "NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"
  _serverless_create >/dev/null 2>&1
  assert_equals 'ADA_24' "$(jq -r '.gpu.pools[0]' "$payload")"
  assert_equals '["NVIDIA RTX PRO 6000 Blackwell Server Edition MIG 1g.24gb"]' "$(jq -c '.gpu.excludedTypes' "$payload")"
  rp::http() { :; }
  rp::graphql() { :; }
  rm -f "$payload"
}

# An exclusion outside the hub listing's pool selection must die locally
# (exit 2) without reaching the API.
function test_should_reject_excluded_type_outside_pools_on_hub_path() {
  local fixture
  fixture="$(jq -c -n --arg img 'vllm:1' --arg cfg '{"gpuIds":"ADA_24","gpuCount":1,"containerDiskInGb":20}' \
    '{listing:{id:"h1",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::http() {
    case "$1 $2" in
    'GET /serverless') printf '{"endpoints":[]}' ;;
    'GET /catalog/gpus'*) printf '{"gpus":[{"id":"NVIDIA L4","pool":"ADA_24"},{"id":"NVIDIA A40","pool":"AMPERE_48"}]}' ;;
    esac
  }
  rp::graphql() { printf '%s' "$fixture"; }
  rp::args_parse --hub-id h1 --name glm --exclude-gpu "NVIDIA A40"
  (_serverless_create >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
  rp::graphql() { :; }
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

# --- worker affinity (load-balanced endpoints): --worker-id / --affinity ------

# The X-Runpod-Worker-Id request-header grammar is "[mode ]<worker-id>": a bare
# id is soft affinity (best-effort; there is no literal "soft" token on the
# wire), strict / strict-resume prefix the id. The helper emits the full header
# line so run can splice it into rp::http_api's extra-headers argument; the
# mapping is asserted directly.
function test_should_map_affinity_flags_to_header_value() {
  local v
  rp::args_parse e1
  _serverless_worker_affinity_header v
  assert_equals "" "$v"
  rp::args_parse e1 --worker-id pod-1
  _serverless_worker_affinity_header v
  assert_equals "X-Runpod-Worker-Id: pod-1" "$v"
  rp::args_parse e1 --worker-id pod-1 --affinity soft
  _serverless_worker_affinity_header v
  assert_equals "X-Runpod-Worker-Id: pod-1" "$v"
  rp::args_parse e1 --worker-id pod-1 --affinity strict
  _serverless_worker_affinity_header v
  assert_equals "X-Runpod-Worker-Id: strict pod-1" "$v"
  rp::args_parse e1 --worker-id pod-1 --affinity strict-resume
  _serverless_worker_affinity_header v
  assert_equals "X-Runpod-Worker-Id: strict-resume pod-1" "$v"
}

# A mode without a worker id can't build the header — usage error.
function test_should_exit_usage_when_affinity_without_worker_id() {
  local v
  rp::args_parse e1 --affinity strict
  (_serverless_worker_affinity_header v >/dev/null 2>&1)
  assert_exit_code 2
}

function test_should_exit_usage_when_affinity_mode_unknown() {
  local v
  rp::args_parse e1 --worker-id pod-1 --affinity pin
  (_serverless_worker_affinity_header v >/dev/null 2>&1)
  assert_exit_code 2
}

# The worker id must be a well-formed id: it is interpolated into a header
# value, so the charset guard also rules out header injection.
function test_should_exit_usage_when_worker_id_is_not_an_id() {
  rp::args_parse e1 --input '{}' --worker-id 'bad id'
  (_serverless_run >/dev/null 2>&1)
  assert_exit_code 2
}

# run forwards the affinity header as rp::http_api's 5th argument (the
# transport threads it into the request-header file). Bare id = soft.
function test_should_send_worker_affinity_header_on_run() {
  local meta
  meta="$(mktemp)"
  rp::http_api() {
    printf '%s %s %s [%s]' "$1" "$2" "${4:-}" "${5:-}" >"$meta"
    printf '{"status":"COMPLETED"}'
  }
  rp::args_parse e1 --input '{}' --worker-id pod-1
  _serverless_run >/dev/null 2>&1
  assert_equals "POST /e1/runsync 300 [X-Runpod-Worker-Id: pod-1]" "$(<"$meta")"
  rp::http_api() { :; }
  rm -f "$meta"
}

# The header composes with --async unchanged: same value, /run route.
function test_should_compose_affinity_with_async_route() {
  local meta out
  meta="$(mktemp)"
  rp::http_api() {
    printf '%s %s %s [%s]' "$1" "$2" "${4:-}" "${5:-}" >"$meta"
    printf '{"id":"job-42","status":"IN_QUEUE"}'
  }
  rp::args_parse e1 --input '{}' --async --worker-id pod-1 --affinity strict-resume
  out="$(_serverless_run 2>/dev/null)"
  assert_equals "POST /e1/run 300 [X-Runpod-Worker-Id: strict-resume pod-1]" "$(<"$meta")"
  assert_equals "job-42" "$out"
  rp::http_api() { :; }
  rm -f "$meta"
}

# Human mode surfaces the responding worker (the X-Runpod-Worker-Id response
# header the transport captures) so pinning composes: run → see worker → pin
# the next request. --json stays clean.
function test_should_print_served_by_worker_on_human_run() {
  rp::http_api() { printf '{"status":"COMPLETED"}'; }
  _RP_WORKER_ID="pod-9"
  local err
  rp::args_parse e1 --input '{}'
  err="$(_serverless_run 2>&1 >/dev/null)"
  assert_contains "served by worker: pod-9" "$err"
  err="$(rp::cmd_serverless run e1 --input '{}' --json 2>&1 >/dev/null)"
  assert_not_contains "served by worker" "$err"
  _RP_WORKER_ID=""
  rp::http_api() { :; }
}

# No served-by line when the endpoint did not send the response header
# (queue-based endpoints don't).
function test_should_omit_served_by_worker_without_response_header() {
  rp::http_api() { printf '{"status":"COMPLETED"}'; }
  _RP_WORKER_ID=""
  local err
  rp::args_parse e1 --input '{}'
  err="$(_serverless_run 2>&1 >/dev/null)"
  assert_not_contains "served by worker" "$err"
  rp::http_api() { :; }
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
  rp::cmd_serverless create --template t --name e1 --gpu "NVIDIA L4" >/dev/null 2>&1
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

# The renamed `serverless` command module is the canonical target; the old
# `endpoint` resource name is gone (full removal, no deprecation shim).
function test_should_route_serverless_list_through_renamed_module() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '[]'
  }
  . "$RP_ROOT/commands/serverless.sh"
  rp::cmd_serverless list >/dev/null 2>&1
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

# rp serverless status e1 job-1 — data-plane GET /e1/status/job-1, exit 0 on COMPLETED.
function test_should_get_status_on_data_plane_when_status_given() {
  local cap rc
  cap="$(mktemp)"
  rp::http_api() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"id":"job-1","status":"COMPLETED","output":{"ok":true}}'
  }
  rp::cmd_serverless status e1 job-1 >/dev/null 2>&1
  rc=$?
  assert_equals "GET /e1/status/job-1" "$(<"$cap")"
  assert_equals 0 "$rc"
  rp::http_api() { :; }
  rm -f "$cap"
}

# status reuses the shared _serverless_status_exit mapping (COMPLETED handled
# above); the terminal-failure states map to exit 1, non-terminal to 0.
function test_should_map_terminal_status_to_exit_code() {
  local s rc
  for s in FAILED CANCELLED TIMED_OUT; do
    rp::http_api() { printf '{"id":"j","status":"%s"}' "$s"; }
    rp::cmd_serverless status e1 j >/dev/null 2>&1
    rc=$?
    assert_equals 1 "$rc" "status $s should exit 1"
  done
  for s in IN_QUEUE IN_PROGRESS ''; do
    rp::http_api() { printf '{"id":"j","status":"%s"}' "$s"; }
    rp::cmd_serverless status e1 j >/dev/null 2>&1
    rc=$?
    assert_equals 0 "$rc" "status '$s' should exit 0"
  done
  rp::http_api() { :; }
}

# The status→exit mapping lives in one shared helper, not reimplemented per
# verb: assert _serverless_status_exit directly.
function test_should_centralise_status_exit_mapping_in_helper() {
  _serverless_status_exit COMPLETED
  assert_equals 0 $?
  _serverless_status_exit FAILED
  assert_equals 1 $?
  _serverless_status_exit CANCELLED
  assert_equals 1 $?
  _serverless_status_exit TIMED_OUT
  assert_equals 1 $?
  _serverless_status_exit IN_QUEUE
  assert_equals 0 $?
  _serverless_status_exit IN_PROGRESS
  assert_equals 0 $?
}

# status --json still emits the raw envelope and keeps the exit mapping.
function test_should_emit_raw_envelope_on_status_json() {
  local cap
  cap="$(mktemp)"
  rp::http_api() {
    printf '%s' "$1 $2" >"$cap"
    printf '{"id":"job-1","status":"FAILED","error":"boom"}'
  }
  local out rc
  out="$(rp::cmd_serverless status e1 job-1 --json 2>/dev/null)"
  rc=$?
  assert_equals '{"id":"job-1","status":"FAILED","error":"boom"}' "$out"
  assert_equals 1 "$rc"
  rp::http_api() { :; }
  rm -f "$cap"
}

# status requires both the endpoint id and the job id.
function test_should_exit_usage_when_status_missing_job_id() {
  rp::http_api() { :; }
  (rp::cmd_serverless status e1 >/dev/null 2>&1)
  assert_exit_code 2
}

# rp serverless health e1 — data-plane GET /e1/health, worker + job histogram.
function test_should_get_health_on_data_plane_and_print_counts() {
  local cap out
  cap="$(mktemp)"
  rp::http_api() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"jobs":{"completed":1,"failed":5,"inProgress":0,"inQueue":2,"retried":0},"workers":{"idle":0,"running":0}}'
  }
  out="$(rp::cmd_serverless health e1 2>/dev/null)"
  assert_equals "GET /e1/health" "$(<"$cap")"
  assert_contains "workers:" "$out"
  assert_contains "jobs:" "$out"
  assert_contains "completed=1" "$out"
  assert_contains "failed=5" "$out"
  assert_contains "inQueue=2" "$out"
  rp::http_api() { :; }
  rm -f "$cap"
}

# health --json passes the raw envelope through.
function test_should_emit_raw_envelope_on_health_json() {
  local envelope='{"jobs":{"completed":1,"failed":5,"inProgress":0,"inQueue":2,"retried":0},"workers":{"idle":0,"running":0}}'
  rp::http_api() { printf '%s' "$envelope"; }
  local out
  out="$(rp::cmd_serverless health e1 --json 2>/dev/null)"
  assert_equals "$envelope" "$out"
  rp::http_api() { :; }
}

# health requires an endpoint id.
function test_should_exit_usage_when_health_missing_id() {
  rp::http_api() { :; }
  (rp::cmd_serverless health >/dev/null 2>&1)
  assert_exit_code 2
}

# status and health route through the public dispatcher to the data plane.
function test_should_route_status_and_health_verbs() {
  local cap
  cap="$(mktemp)"
  rp::http_api() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"jobs":{},"workers":{}}'
  }
  rp::cmd_serverless status e1 job-1 >/dev/null 2>&1
  assert_contains "GET /e1/status/job-1" "$(<"$cap")"
  rp::cmd_serverless health e1 >/dev/null 2>&1
  assert_contains "GET /e1/health" "$(<"$cap")"
  rp::http_api() { :; }
  rm -f "$cap"
}

# --- batch sub-resource (control-plane REST) --------------------------------

# Bare `batch` prints the verb help; each verb routes to its control-plane
# method+path under /serverless/{ep}/batch.
function test_should_route_batch_verbs_on_control_plane() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    case "$1 $2" in
    'GET /serverless/e1/batch') printf '{"batches":[{"id":"b1","status":"FINALIZED","requestTotal":10,"requestInProgress":2,"requestCompleted":7,"requestFailed":1}]}' ;;
    'GET /serverless/e1/batch/b1') printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestInProgress":2,"requestCompleted":7,"requestFailed":1}' ;;
    'POST /serverless/e1/batch') printf '{"id":"b1","status":"DRAFT"}' ;;
    'POST /serverless/e1/batch/b1/requests') printf '{"id":"b1"}' ;;
    'POST /serverless/e1/batch/b1/finalize') printf '{"id":"b1","status":"FINALIZED"}' ;;
    'POST /serverless/e1/batch/b1/cancel') printf '{"id":"b1","status":"CANCELLED"}' ;;
    'PUT /serverless/e1/batch/b1') printf '{"id":"b1","name":"renamed"}' ;;
    'DELETE /serverless/e1/batch/b1/requests/r1') printf '{"id":"r1"}' ;;
    *) printf '{}' ;;
    esac
  }
  rp::cmd_serverless batch >/tmp/b_help 2>/dev/null
  assert_contains "Usage: rp serverless batch" "$(<"/tmp/b_help")"
  rp::cmd_serverless batch list e1 >/dev/null 2>&1
  assert_contains "GET /serverless/e1/batch" "$(<"$cap")"
  rp::cmd_serverless batch get e1 b1 >/dev/null 2>&1
  assert_contains "GET /serverless/e1/batch/b1" "$(<"$cap")"
  rp::cmd_serverless batch create e1 >/dev/null 2>&1
  assert_contains "POST /serverless/e1/batch" "$(<"$cap")"
  rp::cmd_serverless batch add e1 b1 --input '{"t":1}' >/dev/null 2>&1
  assert_contains "POST /serverless/e1/batch/b1/requests" "$(<"$cap")"
  rp::cmd_serverless batch finalize e1 b1 >/dev/null 2>&1
  assert_contains "POST /serverless/e1/batch/b1/finalize" "$(<"$cap")"
  rp::cmd_serverless batch cancel e1 b1 >/dev/null 2>&1
  assert_contains "POST /serverless/e1/batch/b1/cancel" "$(<"$cap")"
  rp::cmd_serverless batch update e1 b1 --name renamed >/dev/null 2>&1
  assert_contains "PUT /serverless/e1/batch/b1" "$(<"$cap")"
  rp::cmd_serverless batch remove e1 b1 r1 >/dev/null 2>&1
  assert_contains "DELETE /serverless/e1/batch/b1/requests/r1" "$(<"$cap")"
  rp::http() { :; }
  rm -f "$cap" /tmp/b_help
}

# create sends a top-level array: --input values become {input} elements, and
# with no input flags the body is [].
function test_should_send_top_level_array_on_batch_create() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"b1","status":"DRAFT"}'
  }
  rp::args_parse e1 --input '{"t":1}' --input '{"t":2}'
  _serverless_batch_create 2>/dev/null
  assert_equals '2' "$(jq -r 'length' "$cap")"
  assert_equals '1' "$(jq -r '.[0].input.t' "$cap")"
  rp::args_parse e1
  _serverless_batch_create 2>/dev/null
  assert_equals '0' "$(jq -r 'length' "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

# add wraps into the {"requests":[...]} envelope the append endpoint expects.
function test_should_wrap_requests_envelope_on_batch_add() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"b1"}'
  }
  rp::args_parse e1 b1 --input '{"t":1}'
  _serverless_batch_add 2>/dev/null
  assert_equals '1' "$(jq -r '.requests | length' "$cap")"
  assert_equals '1' "$(jq -r '.requests[0].input.t' "$cap")"
  rp::http() { :; }
  rm -f "$cap"
}

# --input-file may hold an array of inputs; combined with --input the file
# comes first and every element lands as {input: ...}.
function test_should_merge_input_file_first_on_batch_add() {
  local infile cap
  infile="$(mktemp)"
  cap="$(mktemp)"
  printf '[{"from":"file"}]' >"$infile"
  rp::http() {
    printf '%s' "${3:-}" >"$cap"
    printf '{"id":"b1"}'
  }
  rp::args_parse e1 b1 --input-file "$infile" --input '{"from":"flag"}'
  _serverless_batch_add 2>/dev/null
  assert_equals '2' "$(jq -r '.requests | length' "$cap")"
  assert_equals 'file' "$(jq -r '.requests[0].input.from' "$cap")"
  assert_equals 'flag' "$(jq -r '.requests[1].input.from' "$cap")"
  rp::http() { :; }
  rm -f "$infile" "$cap"
}

# Invalid JSON in --input or a non-array --input-file dies locally (exit 2),
# before any HTTP call.
function test_should_exit_usage_on_invalid_batch_inputs() {
  rp::http() { :; }
  rp::args_parse e1 --input 'not-json{'
  (_serverless_batch_create >/dev/null 2>&1)
  assert_exit_code 2
  printf '{"not":"an-array"}' >/tmp/b_file
  rp::args_parse e1 b1 --input-file /tmp/b_file
  (_serverless_batch_add >/dev/null 2>&1)
  assert_exit_code 2
  rp::http() { :; }
  rm -f /tmp/b_file
}

# A payload past the 10 MiB append cap errors before the POST.
function test_should_error_before_post_when_batch_add_exceeds_10mib() {
  local marker infile pad
  marker="$(mktemp)"
  infile="$(mktemp)"
  pad="$(mktemp)"
  head -c 6000000 /dev/zero | tr '\0' 'x' >"$pad"
  jq -c -n --rawfile p "$pad" '[{input:{pad:$p}},{input:{pad:$p}}]' >"$infile"
  rp::http() {
    printf 'POSTED' >>"$marker"
    printf '{"id":"b1"}'
  }
  rp::args_parse e1 b1 --input-file "$infile"
  (_serverless_batch_add >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker" "$infile" "$pad"
}

# Missing operands exit usage: list/get/add/finalize/cancel/update/remove and
# create all require their positional ids (create: the endpoint).
function test_should_exit_usage_when_batch_operands_missing() {
  rp::http() { :; }
  local verb
  for verb in list get create; do
    (rp::cmd_serverless batch "$verb" >/dev/null 2>&1)
    assert_exit_code 2 "batch $verb with no endpoint should exit 2"
  done
  for verb in add finalize cancel update; do
    (rp::cmd_serverless batch "$verb" e1 >/dev/null 2>&1)
    assert_exit_code 2 "batch $verb without a batch id should exit 2"
  done
  (rp::cmd_serverless batch remove e1 b1 >/dev/null 2>&1)
  assert_exit_code 2
}

# Human list renders a table from the batches envelope; --json passes the raw
# envelope through.
function test_should_render_batch_list_table_and_raw_json() {
  rp::http() {
    printf '{"batches":[{"id":"b1","name":"nightly","status":"FINALIZED","requestTotal":10,"requestInProgress":2,"requestCompleted":7,"requestFailed":1}]}'
  }
  local out
  out="$(rp::cmd_serverless batch list e1 2>/dev/null)"
  assert_contains "b1" "$out"
  assert_contains "FINALIZED" "$out"
  out="$(rp::cmd_serverless batch list e1 --json 2>/dev/null)"
  assert_contains '"batches"' "$out"
  rp::http() { :; }
}

# get prints the progress headline (stderr for humans, empty under --json).
function test_should_print_progress_headline_on_batch_get() {
  rp::http() { printf '{"id":"b1","status":"FINALIZED","requestTotal":1000,"requestInProgress":8,"requestCompleted":244,"requestFailed":6}'; }
  local out err
  err="$(rp::cmd_serverless batch get e1 b1 2>&1 >/dev/null)"
  assert_contains "244/1000" "$err"
  assert_contains "failed=6" "$err"
  out="$(rp::cmd_serverless batch get e1 b1 --json 2>/dev/null)"
  assert_contains '"requestTotal":1000' "$out"
  rp::http() { :; }
}

# get --wait polls until completed+failed equals the total; the double returns
# an in-flight summary then a reconciled one, and the final exit is 0.
function test_should_poll_until_counts_reconcile_on_batch_get_wait() {
  local cc
  cc="$(mktemp)"
  printf '0' >"$cc"
  rp::http() {
    local c
    c="$(cat "$cc")"
    c=$((c + 1))
    printf '%s' "$c" >"$cc"
    if ((c == 1)); then
      printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestInProgress":2,"requestCompleted":7,"requestFailed":1}'
    else
      printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestInProgress":0,"requestCompleted":10,"requestFailed":0}'
    fi
  }
  local rc
  rp::args_parse e1 b1 --wait --interval 0
  _serverless_batch_get >/dev/null 2>&1
  rc=$?
  assert_equals 0 "$rc"
  assert_equals 2 "$(cat "$cc")"
  rp::http() { :; }
  rm -f "$cc"
}

# get --wait exits 1 when the batch itself reaches a terminal failure state.
function test_should_exit_1_on_terminal_batch_state_in_wait() {
  local cc
  cc="$(mktemp)"
  printf '0' >"$cc"
  rp::http() {
    local c
    c="$(cat "$cc")"
    c=$((c + 1))
    printf '%s' "$c" >"$cc"
    if ((c == 1)); then
      printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestInProgress":2,"requestCompleted":7,"requestFailed":1}'
    else
      printf '{"id":"b1","status":"CANCELLED","requestTotal":10,"requestInProgress":1,"requestCompleted":7,"requestFailed":1}'
    fi
  }
  local rc
  rp::args_parse e1 b1 --wait --interval 0
  (_serverless_batch_get >/dev/null 2>&1)
  rc=$?
  assert_equals 1 "$rc"
  rp::http() { :; }
  rm -f "$cc"
}

# requests pages through child requests; --status filters client-side, and
# offset/limit compose onto the query string.
function test_should_page_and_filter_batch_requests() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"requests":[{"id":"r1","status":"COMPLETED","output":{"ok":true}},{"id":"r2","status":"FAILED","error":"boom"}],"total":2,"offset":0,"limit":50,"hasMore":false}'
  }
  local out
  out="$(rp::cmd_serverless batch requests e1 b1 2>/dev/null)"
  assert_contains "r1" "$out"
  assert_contains "r2" "$out"
  rp::cmd_serverless batch requests e1 b1 --status failed --cursor 10 --limit 5 >/dev/null 2>&1
  assert_contains "offset=10" "$(<"$cap")"
  assert_contains "limit=5" "$(<"$cap")"
  out="$(rp::cmd_serverless batch requests e1 b1 --status failed 2>/dev/null)"
  assert_contains "r2" "$out"
  assert_not_contains "r1" "$out"
  rp::http() { :; }
  rm -f "$cap"
}

# create prints the new batch id on stdout and the confirmation on stderr.
function test_should_print_batch_id_on_create_and_confirmation_on_stderr() {
  rp::http() { printf '{"id":"b9","status":"DRAFT"}'; }
  rp::args_parse e1
  local out err
  out="$(_serverless_batch_create 2>/tmp/b_err)"
  err="$(cat /tmp/b_err)"
  assert_equals "b9" "$out"
  assert_contains "b9" "$err"
  rp::http() { :; }
  rm -f /tmp/b_err
}

# ---------------------------------------------------------------------------
# Batch sub-resource (BETA): endpoint-scoped bulk inference on the control plane.

# rp serverless batch list e1 — control-plane GET /serverless/e1/batch.
function test_should_route_batch_list_to_endpoint_scoped_get() {
  local cap out
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    printf '{"batches":[{"id":"b1","status":"FINALIZED","requestTotal":10,"requestCompleted":4,"requestFailed":1,"requestInProgress":2}]}'
  }
  out="$(rp::cmd_serverless batch list e1 2>/dev/null)"
  assert_equals "GET /serverless/e1/batch" "$(<"$cap")"
  assert_contains "b1" "$out"
  rp::http() { :; }
  rm -f "$cap"
}

# Bare `rp serverless batch` prints the verb help (the registry delegations
# convention: explicit verbs only, no implicit list).
function test_should_show_batch_help_when_bare_batch_given() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_serverless batch >"$tmp" 2>/dev/null
  assert_contains "Usage: rp serverless batch" "$(<"$tmp")"
  rm -f "$tmp"
}

# rp serverless batch create e1 with no input flags — POSTs a top-level empty
# array and prints the new batch id on stdout.
function test_should_post_empty_array_on_bare_batch_create() {
  local cap_f body_f out
  cap_f="$(mktemp)"
  body_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '%s' "${3:-}" >"$body_f"
    printf '{"id":"b-new","status":"DRAFT"}'
  }
  out="$(rp::cmd_serverless batch create e1 2>/dev/null)"
  assert_equals "POST /serverless/e1/batch" "$(<"$cap_f")"
  assert_equals "[]" "$(<"$body_f")"
  assert_equals "b-new" "$out"
  rp::http() { :; }
  rm -f "$cap_f" "$body_f"
}

# Each repeatable --input becomes one {"input":...} element of the array.
function test_should_wrap_repeatable_inputs_into_array_on_create() {
  local body_f
  body_f="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body_f"
    printf '{"id":"b-new","status":"DRAFT"}'
  }
  rp::cmd_serverless batch create e1 --input '{"text":"a"}' --input '{"text":"b"}' >/dev/null 2>&1
  assert_equals '2' "$(jq 'length' "$body_f")"
  assert_equals 'a' "$(jq -r '.[0].input.text' "$body_f")"
  assert_equals 'b' "$(jq -r '.[1].input.text' "$body_f")"
  rp::http() { :; }
  rm -f "$body_f"
}

# rp serverless batch add e1 b1 --input … — wraps into the {"requests":[…]}
# envelope the append endpoint expects.
function test_should_wrap_inputs_in_requests_envelope_on_add() {
  local body_f
  body_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$body_f.path"
    printf '%s' "${3:-}" >"$body_f"
    printf '{"added":2}'
  }
  rp::cmd_serverless batch add e1 b1 --input '{"text":"a"}' --input '{"text":"b"}' >/dev/null 2>&1
  assert_equals "POST /serverless/e1/batch/b1/requests" "$(<"$body_f.path")"
  assert_equals '2' "$(jq '.requests | length' "$body_f")"
  assert_equals 'a' "$(jq -r '.requests[0].input.text' "$body_f")"
  rp::http() { :; }
  rm -f "$body_f" "$body_f.path"
}

# --input-file (array of inputs) merges before repeatable --input values.
function test_should_merge_input_file_before_repeatable_inputs_on_add() {
  local body_f infile
  body_f="$(mktemp)"
  infile="$(mktemp)"
  printf '[{"text":"f1"},{"text":"f2"}]' >"$infile"
  rp::http() {
    printf '%s' "${3:-}" >"$body_f"
    printf '{"added":3}'
  }
  rp::cmd_serverless batch add e1 b1 --input-file "$infile" --input '{"text":"i1"}' >/dev/null 2>&1
  assert_equals '3' "$(jq '.requests | length' "$body_f")"
  assert_equals 'f1' "$(jq -r '.requests[0].input.text' "$body_f")"
  assert_equals 'i1' "$(jq -r '.requests[2].input.text' "$body_f")"
  rp::http() { :; }
  rm -f "$body_f" "$infile"
}

# --input-file may be - (stdin), like rp serverless run --input-file -.
function test_should_read_add_inputs_from_stdin_when_input_file_is_dash() {
  local body_f
  body_f="$(mktemp)"
  rp::http() {
    printf '%s' "${3:-}" >"$body_f"
    printf '{"added":1}'
  }
  printf '[{"text":"s"}]' | rp::cmd_serverless batch add e1 b1 --input-file - >/dev/null 2>&1
  assert_equals '1' "$(jq '.requests | length' "$body_f")"
  assert_equals 's' "$(jq -r '.requests[0].input.text' "$body_f")"
  rp::http() { :; }
  rm -f "$body_f"
}

# Invalid --input JSON dies locally (exit 2) before any POST.
function test_should_exit_usage_before_post_when_add_input_is_invalid_json() {
  local cap_f
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"$cap_f"
    printf '{}'
  }
  (rp::cmd_serverless batch add e1 b1 --input 'not-json{' >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f"
}

# A payload over the API's 10 MiB append limit dies locally, before the POST,
# with guidance to split into multiple add calls.
function test_should_exit_usage_before_post_when_add_payload_exceeds_10mib() {
  local cap_f big infile
  cap_f="$(mktemp)"
  big="$(printf 'x%.0s' $(seq 1 2000000))" # ~2MB per input, three inputs > 6MB… padded below
  infile="$(mktemp)"
  jq -cn --arg pad "$big" '[{input:{pad:$pad}},{input:{pad:$pad}},{input:{pad:$pad}},{input:{pad:$pad}},{input:{pad:$pad}},{input:{pad:$pad}}]' >"$infile"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >>"$cap_f"
    printf '{}'
  }
  (rp::cmd_serverless batch add e1 b1 --input-file "$infile" >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f" "$infile"
}

# finalize locks a DRAFT batch: POST /serverless/{ep}/batch/{id}/finalize.
function test_should_post_finalize_path_on_finalize() {
  local cap_f
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{"id":"b1","status":"FINALIZED"}'
  }
  rp::cmd_serverless batch finalize e1 b1 >/dev/null 2>&1
  assert_equals "POST /serverless/e1/batch/b1/finalize" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f"
}

# cancel stops a batch: POST /serverless/{ep}/batch/{id}/cancel (no prompt,
# per house style).
function test_should_post_cancel_path_on_cancel() {
  local cap_f
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{"id":"b1","status":"CANCELLED"}'
  }
  rp::cmd_serverless batch cancel e1 b1 >/dev/null 2>&1
  assert_equals "POST /serverless/e1/batch/b1/cancel" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f"
}

# remove drops one request from a DRAFT batch: DELETE .../requests/{reqId}.
function test_should_delete_request_path_on_remove() {
  local cap_f
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{}'
  }
  rp::cmd_serverless batch remove e1 b1 r1 >/dev/null 2>&1
  assert_equals "DELETE /serverless/e1/batch/b1/requests/r1" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f"
}

# finalize requires both the endpoint id and the batch id.
function test_should_exit_usage_when_finalize_missing_batch_id() {
  rp::http() { :; }
  (rp::cmd_serverless batch finalize e1 >/dev/null 2>&1)
  assert_exit_code 2
}

# rp serverless batch get e1 b1 — GET summary; human mode prints a progress
# headline to stderr (counts; completion inferred from completed+failed=total).
function test_should_print_batch_summary_headline_on_get() {
  local cap_f err
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{"id":"b1","endpointId":"e1","status":"FINALIZED","requestTotal":1000,"requestInProgress":8,"requestCompleted":244,"requestFailed":6,"createdAt":1783584000000}'
  }
  rp::cmd_serverless batch get e1 b1 >/dev/null 2>/tmp/bget_err
  err="$(cat /tmp/bget_err)"
  assert_equals "GET /serverless/e1/batch/b1" "$(<"$cap_f")"
  assert_contains "FINALIZED" "$err"
  assert_contains "244/1000" "$err"
  assert_contains "failed=6" "$err"
  rp::http() { :; }
  rm -f "$cap_f" /tmp/bget_err
}

# get --json emits the raw envelope verbatim and nothing on stderr.
function test_should_emit_raw_envelope_on_batch_get_json() {
  local envelope='{"id":"b1","status":"FINALIZED","requestTotal":1000,"requestCompleted":244,"requestFailed":6}'
  rp::http() { printf '%s' "$envelope"; }
  local out err
  out="$(rp::cmd_serverless batch get e1 b1 --json 2>/tmp/bget_err)"
  err="$(cat /tmp/bget_err)"
  assert_equals "$envelope" "$out"
  assert_equals "" "$err"
  rp::http() { :; }
  rm -f /tmp/bget_err
}

# rp serverless batch requests e1 b1 — server-paginated child listing:
# GET /serverless/{ep}/batch/{id}/requests, table of id/status/error.
function test_should_get_paginated_requests_path_and_table() {
  local cap_f out
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{"requests":[{"id":"r1","status":"COMPLETED","output":{"ok":true}},{"id":"r2","status":"FAILED","error":"timeout exceeded"}],"total":1000,"offset":0,"limit":50,"hasMore":true}'
  }
  out="$(rp::cmd_serverless batch requests e1 b1 2>/dev/null)"
  assert_equals "GET /serverless/e1/batch/b1/requests" "$(<"$cap_f")"
  assert_contains "r1" "$out"
  assert_contains "COMPLETED" "$out"
  assert_contains "timeout exceeded" "$out"
  rp::http() { :; }
  rm -f "$cap_f"
}

# --limit/--cursor forward as the server's limit/offset query params (the
# contract lib/paginate.sh documents for when server pagination exists).
function test_should_forward_limit_and_cursor_as_query_params_on_requests() {
  local cap_f
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '{"requests":[],"total":0,"offset":50,"limit":25,"hasMore":false}'
  }
  rp::cmd_serverless batch requests e1 b1 --limit 25 --cursor 50 >/dev/null 2>&1
  assert_equals "GET /serverless/e1/batch/b1/requests?offset=50&limit=25" "$(<"$cap_f")"
  rp::http() { :; }
  rm -f "$cap_f"
}

# --status filters client-side (the API documents no status query param), so
# `--status completed` is the "give me my results" view.
function test_should_filter_requests_by_status_client_side() {
  local out
  rp::http() {
    printf '{"requests":[{"id":"r1","status":"COMPLETED"},{"id":"r2","status":"FAILED","error":"boom"}],"total":2,"offset":0,"limit":50,"hasMore":false}'
  }
  out="$(rp::cmd_serverless batch requests e1 b1 --status completed 2>/dev/null)"
  assert_contains "r1" "$out"
  assert_not_contains "r2" "$out"
  rp::http() { :; }
}

# requests --json passes the raw envelope through.
function test_should_emit_raw_envelope_on_batch_requests_json() {
  local envelope='{"requests":[{"id":"r1","status":"COMPLETED"}],"total":1,"offset":0,"limit":50,"hasMore":false}'
  rp::http() { printf '%s' "$envelope"; }
  local out
  out="$(rp::cmd_serverless batch requests e1 b1 --json 2>/dev/null)"
  assert_equals "$envelope" "$out"
  rp::http() { :; }
}

# update renames a batch: PUT /serverless/{ep}/batch/{id} with the name field.
function test_should_put_name_on_batch_update() {
  local cap_f body_f
  cap_f="$(mktemp)"
  body_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    printf '%s' "${3:-}" >"$body_f"
    printf '{"id":"b1","name":"nightly-embeddings"}'
  }
  rp::cmd_serverless batch update e1 b1 --name nightly-embeddings >/dev/null 2>&1
  assert_equals "PUT /serverless/e1/batch/b1" "$(<"$cap_f")"
  assert_equals "nightly-embeddings" "$(jq -r '.name' "$body_f")"
  rp::http() { :; }
  rm -f "$cap_f" "$body_f"
}

# --wait polls until completed+failed equals total; progress headlines hit
# stderr only when the done-count changes; exit 0 even with failed requests
# (request failures are data, surfaced via `requests`).
function test_should_wait_until_counts_reconcile_on_get_wait() {
  local cap_f err rc
  cap_f="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap_f"
    local n
    local n prev
    prev="$(cat "$cap_f.cnt" 2>/dev/null || true)"
    n=$((${prev:-0} + 1))
    printf '%s' "$n" >"$cap_f.cnt"
    if ((n < 2)); then
      printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestCompleted":4,"requestFailed":0,"requestInProgress":6}'
    else
      printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestCompleted":9,"requestFailed":1,"requestInProgress":0}'
    fi
  }
  rp::cmd_serverless batch get e1 b1 --wait --interval 0 >/dev/null 2>/tmp/bwait_err
  rc=$?
  err="$(cat /tmp/bwait_err)"
  assert_equals 0 "$rc"
  assert_contains "done=4/10" "$err"
  assert_contains "done=9/10" "$err"
  rp::http() { :; }
  rm -f "$cap_f" "$cap_f.cnt" /tmp/bwait_err
}

# A batch that lands in terminal FAILED exits 1 (distinct from per-request
# failures, which never move the batch's own status).
function test_should_exit_1_when_wait_reaches_terminal_failed() {
  rp::http() { printf '{"id":"b1","status":"FAILED","requestTotal":10,"requestCompleted":4,"requestFailed":6,"requestInProgress":0}'; }
  (rp::cmd_serverless batch get e1 b1 --wait --interval 0 >/dev/null 2>&1)
  assert_exit_code 1
  rp::http() { :; }
}

# --timeout expires while the batch is still working → non-zero exit.
function test_should_exit_nonzero_when_wait_times_out() {
  rp::http() { printf '{"id":"b1","status":"FINALIZED","requestTotal":10,"requestCompleted":4,"requestFailed":0,"requestInProgress":6}'; }
  (rp::cmd_serverless batch get e1 b1 --wait --interval 0 --timeout 1 >/dev/null 2>&1)
  assert_exit_code 1
  rp::http() { :; }
}

# --wait --json keeps stdout to a single final envelope (progress is stderr).
function test_should_print_final_envelope_on_wait_json() {
  local out
  rp::http() { printf '{"id":"b1","status":"FINALIZED","requestTotal":2,"requestCompleted":2,"requestFailed":0,"requestInProgress":0}'; }
  out="$(rp::cmd_serverless batch get e1 b1 --wait --interval 0 --json 2>/dev/null)"
  assert_contains '"requestCompleted":2' "$out"
  rp::http() { :; }
}
