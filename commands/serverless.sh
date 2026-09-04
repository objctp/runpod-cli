#!/usr/bin/env bash
#
# Serverless endpoints: deploy, scale, inspect and invoke.
#
# An endpoint runs a container image on demand behind a queue or a load
# balancer, scaling a pool of workers between a minimum and a maximum. The
# image comes from a template or a Hub listing rather than from flags, and jobs
# are submitted on the data plane with `rp serverless run`.
#
# Usage: rp serverless <verb> [flags]
#

# GPU type ranking for --gpus-from-volume: the display names tried, in order,
# against the volume's in-stock catalogue.
RP_DEFAULT_GPU_TYPES=(
  "NVIDIA RTX 4000 Ada Generation"
  "NVIDIA GeForce RTX 4090"
  "NVIDIA L4"
  "NVIDIA A40"
)

# Resolve in-stock serverless GPU type ids for a volume's datacenter. v2 source:
# GET /v2/catalog/gpus?include=AVAILABILITY&product=SERVERLESS.
_resolve_gpus_from_volume() {
  local name="$1" dc
  rp::volume_dc "$name"
  dc="$RP_VOLUME_DC"
  rp::info "resolving in-stock GPUs for NV '$name' (dc=$dc; stock is account-wide)"
  local wantjson
  wantjson="$(rp::json_array "${RP_DEFAULT_GPU_TYPES[@]}")"
  rp::http GET '/catalog/gpus?include=AVAILABILITY&product=SERVERLESS' | rp::unwrap gpus | jq -r --argjson want "$wantjson" '
    map(select(.availability != null and .availability != "NONE"))
    | map(select(.id as $id | $want | index($id)))
    | map(.id) | .[]'
}

# Map a GPU-type CSV to a serverless pool-id CSV, dying with the standard message
# when no pool covers a given type. Centralises the get → validate pair that the
# create/update paths would otherwise repeat (and, in the update path, skip — which
# silently sent an empty pool list instead of erroring).
_serverless_gpu_poolcsv() {
  local gpu="$1" poolcsv
  poolcsv="$(rp::gpu_type_to_pool_csv "$gpu")"
  [[ -n "$poolcsv" ]] || rp::die "could not map GPU types to serverless pool ids: $gpu"
  printf '%s' "$poolcsv"
}

# Resolve --network-volume / --network-volume-id to the volume id and
# datacenter, setting the caller's `nvid` and `dc` locals (name → id via
# rp::volume_dc, id → dc via rp::volume_dc_id).
_serverless_resolve_nv() {
  local nvname
  nvid="$(rp::args_get network-volume-id)"
  nvname="$(rp::args_get network-volume)"
  dc=''
  if [[ -n "$nvname" && -z "$nvid" ]]; then
    rp::volume_dc "$nvname"
    nvid="$RP_VOLUME_ID"
    dc="$RP_VOLUME_DC"
  elif [[ -n "$nvid" ]]; then
    rp::volume_dc_id "$nvid"
    dc="$RP_VOLUME_DC"
  fi
}

# Resolve the scaling discriminated-union object for a create. Applies the live
# default when no scaler flags are given (QUEUE_DELAY on QUEUE, REQUEST_COUNT on
# LOAD_BALANCER), enforces LOAD_BALANCER => REQUEST_COUNT, and sets two globals —
# `_RP_SCALING_JSON` (the body object) and `_RP_SCALER_TYPE` (resolved arm) — so
# the caller can drop workers.idleTimeout when it would be rejected (REQUEST_COUNT
# scaling). queueDelay defaults to 4s and requestCount to 1 when a scaler type is
# given without a value. Runs in the main shell (no command substitution) so the
# globals land in the caller's scope.
_serverless_scaling_obj() {
  local etype="$1" stype="$2" sval="$3"
  local _out_type
  if [[ -z "$stype" && -z "$sval" ]]; then
    if [[ "$etype" == "LOAD_BALANCER" ]]; then
      _out_type=REQUEST_COUNT
      sval="$RP_DEFAULT_SCALER_REQUEST_COUNT"
    else
      _out_type=QUEUE_DELAY
      sval="$RP_DEFAULT_SCALER_QUEUE_DELAY_S"
    fi
  else
    _out_type="${stype^^}"
    if [[ -z "$sval" ]]; then
      case "$_out_type" in
      REQUEST_COUNT) sval="$RP_DEFAULT_SCALER_REQUEST_COUNT" ;;
      *) sval="$RP_DEFAULT_SCALER_QUEUE_DELAY_S" ;;
      esac
    fi
  fi
  if [[ "$etype" == "LOAD_BALANCER" && "$_out_type" != "REQUEST_COUNT" ]]; then
    rp::usage "scaling must be REQUEST_COUNT when --type LOAD_BALANCER (got scaler-type '$_out_type')"
  fi
  _RP_SCALER_TYPE="$_out_type"
  _RP_SCALING_JSON="$(rp::json_scaling "$_out_type" "$sval")"
}

_serverless_create() {
  local name
  name="$(rp::args_get name)"
  local hubid
  hubid="$(rp::args_get hub-id)"
  if [[ -n "$hubid" ]]; then
    [[ -z "$(rp::args_get template)" ]] || rp::usage "--hub-id and --template are mutually exclusive"
    _serverless_create_hub "$hubid"
    return $?
  fi

  local template templateid
  template="$(rp::args_get template)"
  templateid="$(rp::args_get template-id)"
  [[ -n "$template" || -n "$templateid" ]] || rp::usage "usage: rp serverless create --template <id>|--template-id <id> [--name <n>] [--gpu <type,..>] [--force] … (see: rp serverless --help; idempotent by name)"
  [[ -n "$name" ]] || rp::usage "usage: rp serverless create --template <id>|--template-id <id> --name <n> [--gpu <type,..>] … (see: rp serverless --help; idempotent by name)"

  # Idempotency gate after the template requirement but before GPU resolution:
  # the v2 --gpu check (and its catalogue lookups) would otherwise exit before
  # rp::resource_create's own gate could run on a re-run.
  if rp::resource_existing serverless "$name"; then
    return 0
  fi

  # Two ways to seed from a template. --template-id is the v2-native field: the
  # API applies the template's container config itself, so we just pass the id.
  # --template (legacy) spreads the container config client-side so explicit
  # flags can override it. --template-id wins when both are given.
  local obj
  if [[ -n "$templateid" ]]; then
    obj='{}'
    rp::obj_set obj templateId "$(rp::json_str "$templateid")"
  else
    obj="$(rp::template_spread "$template")"
  fi

  if [[ -n "$name" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name")"
  fi

  local nvid gpu poolcsv='' dc=''
  local gpusfrom
  gpusfrom="$(rp::args_get gpus-from-volume)"
  gpu="$(rp::args_get gpu)"
  _serverless_resolve_nv
  if [[ -n "$dc" ]]; then
    rp::obj_set obj dataCenterIds "$(rp::json_array "$dc")"
    rp::info "endpoint scoped to NV datacenter: $dc"
    [[ -n "$gpusfrom" ]] && gpu="$(_resolve_gpus_from_volume "$gpusfrom" | paste -sd, -)"
  fi
  if [[ -n "$gpu" ]]; then
    poolcsv="$(_serverless_gpu_poolcsv "$gpu")"
  fi
  if [[ -z "$poolcsv" ]]; then
    rp::usage "rp serverless create requires --gpu <type,..> (or --gpus-from-volume) in API v2"
  fi
  local count
  count="$(rp::args_get_uint gpu-count "$RP_DEFAULT_GPU_COUNT")"
  rp::obj_set obj gpu "$(rp::json_gpu_endpoint "$poolcsv" "$count")"

  # `type` is required by the live spec on create (immutable thereafter).
  local etype idle
  etype="$(rp::args_get type "$RP_DEFAULT_SERVERLESS_TYPE")"
  etype="${etype^^}"
  case "$etype" in
  QUEUE | LOAD_BALANCER) ;;
  *) rp::usage "invalid --type '$etype' (expected QUEUE|LOAD_BALANCER)" ;;
  esac
  rp::obj_set obj type "$(rp::json_str "$etype")"

  local wmin wmax
  wmin="$(rp::args_get_uint workers-min)"
  wmax="$(rp::args_get_uint workers-max)"
  idle="$(rp::args_get_uint idle)"

  # scaling is required on create; default to a valid union arm when no scaler
  # flags are supplied, and honour the LOAD_BALANCER => REQUEST_COUNT rule.
  _serverless_scaling_obj "$etype" "$(rp::args_get scaler-type)" "$(rp::args_get scaler-value)"
  rp::obj_set obj scaling "$_RP_SCALING_JSON"

  # workers.idleTimeout is rejected for REQUEST_COUNT scaling; drop with a note.
  if [[ -n "$idle" && "$_RP_SCALER_TYPE" == "REQUEST_COUNT" ]]; then
    rp::warn "note: --idle (workers.idleTimeout) is ignored with REQUEST_COUNT scaling"
    idle=''
  fi
  if [[ -n "$wmin" || -n "$wmax" || -n "$idle" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax" "$idle")"
  fi

  # FlashBoot enum is OFF|FLASHBOOT|PRIORITY_FLASHBOOT in v2 ("ON" is rejected).
  rp::args_has flashboot && rp::obj_set obj flashboot "$(rp::json_str FLASHBOOT)"

  local mincuda execto
  mincuda="$(rp::args_get min-cuda-version)"
  if [[ -n "$mincuda" ]]; then
    rp::warn "note: --min-cuda-version has no v2 equivalent on create and was ignored (v2 keeps it only as a /catalog/gpus filter)"
  fi
  execto="$(rp::args_get_uint execution-timeout)"
  [[ -n "$execto" ]] && rp::obj_set obj timeout "$((execto * RP_MS_PER_SECOND))"

  local -a nv_arr=()
  [[ -n "$nvid" ]] && nv_arr+=("$nvid")
  if [[ -n "$(rp::args_get network-volume-ids)" ]]; then
    while IFS= read -r x; do [[ -n "$x" ]] && nv_arr+=("$x"); done < <(rp::split_csv "$(rp::args_get network-volume-ids)")
  fi
  if ((${#nv_arr[@]} > 0)); then
    local nvjson
    nvjson="$(rp::json_array "${nv_arr[@]}")"
    rp::obj_set obj networkVolumes "$nvjson"
  fi

  # The template spread already carries the template's env map; --env overlays
  # it key-by-key so the user wins on collision and the rest survives.
  rp::obj_merge_env obj "$(rp::args_get env)"

  local registry
  registry="$(rp::args_get registry)"
  if [[ -n "$registry" ]]; then
    rp::obj_set obj registry "$(rp::json_str "$registry")"
  fi

  rp::resource_create serverless "$name" "$obj"
}

# Deploy straight from a Hub listing. The listing is still fetched via GraphQL
# (Hub has no API v2 endpoint), but the endpoint is created with POST /v2/serverless
# using GPU pool ids (saveEndpoint is gone in v2).
_serverless_create_hub() {
  local hubid="$1"
  local listing image cfg
  listing="$(rp::hub_get "$hubid")"
  [[ -n "$listing" && "$listing" != "null" ]] || rp::notfound "hub listing '$hubid' not found"
  image="$(printf '%s' "$listing" | jq -r '.listedRelease.build.imageName // empty')"
  cfg="$(printf '%s' "$listing" | jq -r '.listedRelease.config // "{}"')"
  [[ -n "$image" ]] || rp::usage "hub listing '$hubid' has no build image"
  local name
  name="$(rp::args_get name)"
  [[ -n "$name" ]] || rp::usage "--hub-id requires --name"

  local gpusfrom gpu poolcsv
  gpusfrom="$(rp::args_get gpus-from-volume)"
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpusfrom" ]]; then
    gpu="$(_resolve_gpus_from_volume "$gpusfrom" | paste -sd, -)"
  fi
  if [[ -n "$gpu" ]]; then
    poolcsv="$(_serverless_gpu_poolcsv "$gpu")"
  else
    poolcsv="$(printf '%s' "$cfg" | jq -r '.gpuIds // empty')"
    [[ -n "$poolcsv" ]] || rp::usage "listing '$hubid' declares no gpuIds — pass --gpu <type,..>"
  fi

  local gpucount cdisk
  gpucount="$(rp::args_get_uint gpu-count "$(printf '%s' "$cfg" | jq -r ".gpuCount // $RP_DEFAULT_GPU_COUNT")")"
  cdisk="$(printf '%s' "$cfg" | jq -r ".containerDiskInGb // $RP_DEFAULT_CONTAINER_DISK_GB")"

  # v2 ContainerConfig.env is an object map {K:"V"}, not [{key,value}].
  local envuser envjson
  envuser="$(rp::args_get env)"
  if [[ -n "$envuser" ]]; then
    envjson="$(rp::env_to_json "$envuser")"
  else
    envjson="$(printf '%s' "$cfg" | jq -c '(.env // []) | map(select(.input.default != null) | {(.key): (.input.default|tostring)}) | add // {}')"
  fi

  local nvid dc=''
  _serverless_resolve_nv
  if [[ -n "$dc" ]]; then
    rp::info "hub endpoint scoped to NV datacenter: $dc"
  fi

  local hwmin hwmax hidle htype hscaling
  hwmin="$(rp::args_get_uint workers-min "$RP_DEFAULT_WORKERS_MIN")"
  hwmax="$(rp::args_get_uint workers-max "$RP_DEFAULT_WORKERS_MAX")"
  hidle="$(rp::args_get_uint idle)"
  htype="$(rp::args_get type "$RP_DEFAULT_SERVERLESS_TYPE")"
  htype="${htype^^}"
  case "$htype" in
  QUEUE | LOAD_BALANCER) ;;
  *) rp::usage "invalid --type '$htype' (expected QUEUE|LOAD_BALANCER)" ;;
  esac
  _serverless_scaling_obj "$htype" "$(rp::args_get scaler-type)" "$(rp::args_get scaler-value)"
  hscaling="$_RP_SCALING_JSON"
  if [[ -n "$hidle" && "$_RP_SCALER_TYPE" == "REQUEST_COUNT" ]]; then
    rp::warn "note: --idle (workers.idleTimeout) is ignored with REQUEST_COUNT scaling"
    hidle=''
  fi
  local body
  body="$(rp::json_obj \
    name "$(rp::json_str "$name")" \
    image "$(rp::json_str "$image")" \
    disk "$cdisk" \
    env "$envjson" \
    type "$(rp::json_str "$htype")" \
    gpu "$(rp::json_gpu_endpoint "$poolcsv" "$gpucount")" \
    scaling "$hscaling" \
    workers "$(rp::json_workers "$hwmin" "$hwmax" "$hidle")")"
  if [[ -n "$nvid" ]]; then
    body="$(_json_merge "$body" "$(rp::json_obj networkVolumes "$(rp::json_array "$nvid")" dataCenterIds "$(rp::json_array "$dc")")")"
  fi
  local hreg
  hreg="$(rp::args_get registry)"
  if [[ -n "$hreg" ]]; then
    body="$(_json_merge "$body" "$(rp::json_obj registry "$(rp::json_str "$hreg")")")"
  fi
  rp::resource_create serverless "$name" "$body" "from hub listing $hubid"
}

_serverless_scale() {
  local id
  rp::require_pos id "usage: rp serverless scale <id> --min N --max N [--idle S]"
  rp::require_id id "$id" "endpoint id"
  local obj='{}' wmin wmax idle
  wmin="$(rp::args_get_uint min)"
  wmax="$(rp::args_get_uint max)"
  idle="$(rp::args_get_uint idle)"
  if [[ -n "$wmin" || -n "$wmax" || -n "$idle" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax" "$idle")"
  fi
  [[ "$obj" != '{}' ]] || rp::usage "nothing to scale (pass --min/--max/--idle)"
  _resource_meta serverless
  local res
  res="$(rp::http PATCH "$RP_RES_PATH/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "scaled endpoint $id"
}

_serverless_update() {
  local id
  rp::require_pos id "usage: rp serverless update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>] [--registry <id>] [--template-id <id>] [--name <n>] [--scale-by delay|requests] [--scale-threshold N]"
  rp::require_id id "$id" "endpoint id"
  _resource_meta serverless
  local obj='{}' gpu
  local wmin wmax idle
  wmin="$(rp::args_get_uint workers-min)"
  wmax="$(rp::args_get_uint workers-max)"
  idle="$(rp::args_get_uint idle)"
  if [[ -n "$wmin" || -n "$wmax" || -n "$idle" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax" "$idle")"
  fi
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpu" ]]; then
    local poolcsv count
    poolcsv="$(_serverless_gpu_poolcsv "$gpu")"
    count="$(rp::args_get_uint gpu-count "$RP_DEFAULT_GPU_COUNT")"
    rp::obj_set obj gpu "$(rp::json_gpu_endpoint "$poolcsv" "$count")"
  fi
  local registry
  registry="$(rp::args_get registry)"
  if [[ -n "$registry" ]]; then
    rp::obj_set obj registry "$(rp::json_str "$registry")"
  fi

  # New field: --template-id swaps the endpoint's template (v2 PATCH field
  # templateId). Distinct from create's --template spread — here only the id is
  # sent, the API applies the template's container config.
  local templateid
  templateid="$(rp::args_get template-id)"
  if [[ -n "$templateid" ]]; then
    rp::obj_set obj templateId "$(rp::json_str "$templateid")"
  fi

  # New field: --name renames the endpoint (PATCH body `name`).
  local name
  name="$(rp::args_get name)"
  if [[ -n "$name" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name")"
  fi

  # Coercion aliases for runpodctl's --scale-by / --scale-threshold. These feed
  # rp's own --scaler-type / --scaler-value (same PATCH `scaling` object), but the
  # value must be translated first, so they are handled in-command rather than in
  # the generic RP_FLAG_ALIASES map. Per D1's collision policy, rp's native flag
  # always wins: the alias only applies when the canonical flag is unset, so
  # `--scaler-type X --scale-by delay` keeps X rather than silently flipping to
  # QUEUE_DELAY.
  local scale_by scale_thr scaler_type scaler_val
  scale_by="$(rp::args_get scale-by)"
  scale_thr="$(rp::args_get scale-threshold)"
  scaler_type="$(rp::args_get scaler-type)"
  scaler_val="$(rp::args_get scaler-value)"
  if [[ -z "$scaler_type" && -n "$scale_by" ]]; then
    case "$scale_by" in
    delay) scaler_type=QUEUE_DELAY ;;
    requests) scaler_type=REQUEST_COUNT ;;
    *) rp::usage "invalid --scale-by '$scale_by' (expected delay|requests)" ;;
    esac
  fi
  if [[ -z "$scaler_val" && -n "$scale_thr" ]]; then
    scaler_val="$scale_thr"
  fi
  if [[ -n "$scaler_type" || -n "$scaler_val" ]]; then
    [[ -n "$scaler_type" ]] || scaler_type=QUEUE_DELAY
    _serverless_scaling_obj "" "$scaler_type" "$scaler_val"
    rp::obj_set obj scaling "$_RP_SCALING_JSON"
  fi

  [[ "$obj" != '{}' ]] || rp::usage "nothing to update"
  local res
  res="$(rp::http PATCH "$RP_RES_PATH/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated endpoint $id"
}

# Build the X-Runpod-Worker-Id request-header line for `run` from --worker-id
# and --affinity, assigning it to the nameref in $1 (empty when neither flag is
# given). The header's value grammar is "[mode ]<worker-id>": a bare id is soft
# affinity (best-effort — there is no literal "soft" token), while strict /
# strict-resume prefix the id and are honoured by load-balanced endpoints only.
# The header name lives here so callers can splice the output straight into
# rp::http_api's extra-headers argument. Runs in the main shell (no command
# substitution) so rp::usage exits the caller; the charset guard on the id also
# rules out header injection.
_serverless_worker_affinity_header() {
  local -n affinity_out="$1"
  local worker mode
  worker="$(rp::args_get worker-id)"
  mode="$(rp::args_get affinity)"
  if [[ -z "$worker" ]]; then
    [[ -z "$mode" ]] || rp::usage "--affinity requires --worker-id <workerId>"
    # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
    affinity_out=""
    return 0
  fi
  rp::require_id worker "$worker" "worker id"
  case "$mode" in
  '' | soft)
    # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
    affinity_out="X-Runpod-Worker-Id: $worker"
    ;;
  strict)
    # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
    affinity_out="X-Runpod-Worker-Id: strict $worker"
    ;;
  strict-resume)
    # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
    affinity_out="X-Runpod-Worker-Id: strict-resume $worker"
    ;;
  *) rp::usage "invalid --affinity '$mode' (expected soft|strict|strict-resume)" ;;
  esac
}

# Submit a job to a deployed endpoint on the data plane (RP_API_BASE). Default
# is /runsync, which blocks until the job completes; --async queues via /run
# and prints the job id. The payload is wrapped through jq's stdin (never
# argv/--argjson) so a base64-heavy --input-file body stays out of `ps`.
# --worker-id/--affinity pin the job to one worker on a load-balanced endpoint
# via the X-Runpod-Worker-Id request header; the same header on the response
# (captured by the transport in _RP_WORKER_ID) is surfaced in human mode so
# the next request can be pinned.
_serverless_run_human() {
  local id="$1" body="$2"
  [[ -n "${_RP_WORKER_ID:-}" ]] && rp::info "served by worker: ${_RP_WORKER_ID}"
  if rp::args_has async; then
    local jobid
    jobid="$(printf '%s' "$body" | jq -r '.id // empty')"
    [[ -n "$jobid" ]] || rp::die "run returned no job id: $body"
    rp::ok "queued job on endpoint $id"
    printf '%s\n' "$jobid"
    return
  fi
  rp::json_pretty "$body"
}

_serverless_run() {
  local id
  rp::require_pos id "usage: rp serverless run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--worker-id <id>] [--affinity soft|strict|strict-resume] [--timeout <s>] [--json]"
  rp::require_id id "$id" "endpoint id"
  rp::args_has sync && rp::args_has async && rp::usage "--sync and --async are mutually exclusive"
  local input file
  input="$(rp::args_get input)"
  file="$(rp::args_get input-file)"
  [[ -n "$input" && -n "$file" ]] && rp::usage "--input and --input-file are mutually exclusive"
  if [[ -n "$file" ]]; then
    if [[ "$file" == - ]]; then
      input="$(cat)"
    else
      [[ -r "$file" ]] || rp::usage "cannot read --input-file '$file'"
      input="$(<"$file")"
    fi
  fi
  [[ -n "$input" ]] || rp::usage "rp serverless run needs --input '<json>' or --input-file <path|->"
  local payload
  payload="$(printf '%s' "$input" | jq -c '{input: .}' 2>/dev/null)" || rp::usage "--input is not valid JSON"
  local route=runsync timeout worker_header
  rp::args_has async && route=run
  timeout="$(rp::args_get_uint timeout 300)"
  _serverless_worker_affinity_header worker_header
  local body
  body="$(rp::http_api POST "/$id/$route" "$payload" "$timeout" "$worker_header")"
  rp::emit_json_or "$body" _serverless_run_human "$id" "$body"
}

# Exit code for a serverless job status: COMPLETED is success (0); the terminal
# failure states FAILED / CANCELLED / TIMED_OUT are 1; any non-terminal state
# (IN_QUEUE / IN_PROGRESS) is 0. Pure (no side effects) so it is unit testable,
# and is the single source of the status→exit mapping on the serverless surface.
_serverless_status_exit() {
  case "$1" in
  COMPLETED) return 0 ;;
  FAILED | CANCELLED | TIMED_OUT) return 1 ;;
  *) return 0 ;;
  esac
}

# Fetch a job's status from the data plane (GET /{id}/status/{jobId}) and render
# it (pretty in human mode, raw with --json), exiting with the job's
# terminal-status code. The only transport it uses is rp::http_api (the
# data-plane seam) — no transport of its own. Mirrors runpodctl's
# `serverless status <id> <job-id>`: stdout is the job payload, exit 0 on
# COMPLETED, 1 on FAILED / CANCELLED / TIMED_OUT (the payload still prints so a
# FAILED job's error is visible), 0 while IN_QUEUE / IN_PROGRESS. The status→exit
# mapping itself lives in the shared _serverless_status_exit helper.
_serverless_status() {
  local id jobid body status
  rp::require_pos_at 0 id "usage: rp serverless status <id> <jobId>"
  rp::require_id id "$id" "endpoint id"
  rp::require_pos_at 1 jobid "usage: rp serverless status <id> <jobId>"
  rp::require_id jobid "$jobid" "job id"
  body="$(rp::http_api GET "/$id/status/$jobid")"
  status="$(printf '%s' "$body" | jq -r '.status // empty')"
  rp::emit_json_or "$body" rp::json_pretty "$body"
  _serverless_status_exit "$status"
}

# Worker/job histogram from the data-plane GET /{id}/health. Prints the workers
# and jobs count sections (runpodctl's "worker and job counts"); with --json the
# raw envelope passes through. Mirrors the `workers` verb's histogram style.
_serverless_health_human() {
  local body="$1"
  printf '%s' "$body" | jq -r '
    "workers: " + ([
      "total=\(.workers.total // 0)",
      "ready=\(.workers.ready // 0)",
      "running=\(.workers.running // 0)",
      "idle=\(.workers.idle // 0)",
      "initializing=\(.workers.initializing // 0)",
      "throttled=\(.workers.throttled // 0)",
      "unhealthy=\(.workers.unhealthy // 0)"
    ] | join("  ")),
    "jobs: " + ([
      "total=\(.jobs.total // 0)",
      "completed=\(.jobs.completed // 0)",
      "failed=\(.jobs.failed // 0)",
      "inProgress=\(.jobs.inProgress // 0)",
      "inQueue=\(.jobs.inQueue // 0)",
      "retried=\(.jobs.retried // 0)"
    ] | join("  "))'
}

# Fetch an endpoint's health (data plane GET /{id}/health) and print the
# worker/job histogram (raw envelope with --json).
_serverless_health() {
  local id
  rp::require_pos_at 0 id "usage: rp serverless health <id>"
  rp::require_id id "$id" "endpoint id"
  local body
  body="$(rp::http_api GET "/$id/health")"
  rp::emit_json_or "$body" _serverless_health_human "$body"
}

# Histogram to stderr; --json passes the raw envelope through.
_serverless_workers() {
  local id
  rp::require_pos id "usage: rp serverless workers <id>"
  rp::require_id id "$id" "endpoint id"
  local body
  body="$(rp::http GET "/serverless/$id/workers")"
  if ! rp::args_has json; then
    rp::info "$(printf '%s' "$body" | jq -r '(.summary // {}) as $s | .endpointVersion as $v | "endpoint v\($v // "?")  workers: total=\($s.total // 0) running=\($s.running // 0) idle=\($s.idle // 0) init=\($s.initializing // 0) throttled=\($s.throttled // 0) unhealthy=\($s.unhealthy // 0)"')"
  fi
  local arr
  arr="$(rp::unwrap workers "$body")"
  rp::emit_json_or "$body" rp::table "$arr" --reshape \
    'map({id, status, stale:(.isStale|tostring), version,
         gpus:.gpuCount, gpuType:.gpuTypeId, dc:.dataCenterId,
         uptime:.uptimeSeconds, image})' \
    id status stale version gpus gpuType dc uptime image
}

# Rollout summary to stderr; per-release diff column from the API's diff array.
_serverless_releases() {
  local id
  rp::require_pos id "usage: rp serverless releases <id>"
  rp::require_id id "$id" "endpoint id"
  local body
  body="$(rp::http GET "/serverless/$id/releases")"
  if ! rp::args_has json; then
    rp::info "$(printf '%s' "$body" | jq -r '(.rollout // {}) as $r | .endpointVersion as $v | "endpoint v\($v // "?")  rollout: \($r.workersOnLatest // 0)/\($r.workersTotal // 0) on latest (\($r.percentOnLatest // 0)%)\(if ($r.inProgress // false) then " — in progress" else "" end)"')"
  fi
  local arr
  arr="$(rp::unwrap releases "$body")"
  rp::emit_json_or "$body" rp::table "$arr" --reshape \
    'map({version:(.version // "?"), source, workers:.workerCount,
         createdAt, build:.buildId,
         diff:((.diff // [])
               | map("\(.field): \(if .old == null then "(none)" else (.old|tostring) end) → \(if .new == null then "(none)" else (.new|tostring) end)")
               | join("; "))})' \
    version source workers createdAt build diff
}

# Live SSE log stream for one worker (getWorkerLogs); --worker is required.
_serverless_logs() {
  local id worker src tail since leid q
  rp::require_pos id "usage: rp serverless logs <id> --worker <workerId> [--source container|system] [--tail N] [--since <rfc3339>] [--last-event-id <ts>]"
  rp::require_id id "$id" "endpoint id"
  worker="$(rp::args_get worker)"
  [[ -n "$worker" ]] || rp::usage "rp serverless logs requires --worker <workerId> (list them with: rp serverless workers $id)"
  rp::require_id worker "$worker" "worker id"
  src="$(rp::args_get source)"
  case "$src" in '' | container | system) ;; *) rp::usage "invalid --source '$src' (expected container|system)" ;; esac
  tail="$(rp::args_get_uint tail)"
  [[ -z "$tail" ]] || ((tail <= RP_LOG_TAIL_MAX)) || rp::usage "--tail must be <= $RP_LOG_TAIL_MAX (got $tail)"
  since="$(rp::args_get since)"
  leid="$(rp::args_get last-event-id)"
  q="$(rp::query_params source "$src" tail "$tail" since "$since")"
  rp::stream_rest "/serverless/$id/workers/$worker/logs$q" "$leid"
}

###
### :::: documentation (rp doc serverless) :::: ##################################
###

# doc: create
# Create a serverless endpoint from a template or a Hub listing.
#
# Usage: rp serverless create --template <id>|--template-id <id> --name <n>
#                             [--gpu <type,..>]
#                             [--network-volume <name> | --network-volume-id <id>
#                              | --network-volume-ids <id,id>]
#                             [--type QUEUE|LOAD_BALANCER] [flags]
#
# Options:
#   --template <id>               template id to deploy (required unless --hub-id
#                                 or --template-id); spread client-side so flags
#                                 can override the template's container config
#   --template-id <id>            v2-native template id (alternative to
#                                 --template); the API applies the template's
#                                 container config, so flags cannot override it
#   --hub-id <listing-id>         deploy from a Hub listing (requires --name;
#                                 mutually exclusive with --template)
#   --name <n>                    endpoint name (required); idempotent by name
#   --gpu <type,..>               GPU type ids (comma-separated) for the pool
#                                 (alias: --gpu-id)
#   --gpus-from-volume <name>     pick in-stock serverless GPU types from a
#                                 fixed four-type preference list (account-wide
#                                 stock, not filtered by the volume's
#                                 datacentre); overrides --gpu — placement is
#                                 pinned by --network-volume, not this flag
#   --network-volume <name>       attach a network volume by name
#   --network-volume-id <id>      attach a network volume by id
#   --network-volume-ids <id,id>  attach several network volumes by id
#   --type QUEUE|LOAD_BALANCER    endpoint type (default: QUEUE)
#   --workers-min N               minimum worker count
#   --workers-max N               maximum worker count
#   --idle S                      workers.idleTimeout; ignored with
#                                 REQUEST_COUNT scaling
#   --gpu-count N                 GPUs per worker (default: 1)
#   --flashboot                   enable FlashBoot (boolean flag)
#   --env K=V                     environment variable; repeatable; merged over
#                                 the template's env on the --template path;
#                                 NOT aliased to runpodctl's --env (a single
#                                 JSON object) — the shapes differ
#   --scaler-type QUEUE_DELAY|REQUEST_COUNT   scaling policy
#   --scaler-value V              scaling threshold (default: 4s / 1 request)
#   --execution-timeout <s>       per-job timeout, sent as milliseconds
#   --registry <id>               registry credential for a private image
#                                 (alias: --registry-auth-id)
#   --force                       skip the name idempotency check
#   --min-cuda-version <ver>      accepted but ignored: v2 keeps it only as a
#                                 /catalog/gpus filter
#
# Notes:
#   --name is required by the live v2 spec on both the --template and --hub-id
#   paths; the CLI checks it up front, so a missing --name fails locally before
#   any request rather than as an API error.
#   --type and --scaling are required by the live v2 spec; when omitted the CLI
#   defaults type to QUEUE and scaling to QUEUE_DELAY with a 4s delay, so a
#   create neither errors nor needs them spelled out.
#   --env is merged over the template's environment on the --template path, so
#   `rp serverless create --template X --env K=V` overrides per key.
#   --idle (workers.idleTimeout) is rejected for REQUEST_COUNT scaling and is
#   ignored with a warning when set.
#   --min-cuda-version is accepted and dropped with a warning: v2 has no
#   create-side CUDA-version field, only the /catalog/gpus filter.
#
# Examples:
# # Deploy a serverless endpoint from a template
# $ rp serverless create --name ocr --template tmpl_abc --gpu "NVIDIA L4"
# # Deploy from a Hub listing
# $ rp serverless create --name diff --hub-id hub_xyz --gpu "NVIDIA A40"
#
# API: POST /v2/serverless

# doc: list
# List your endpoints: id, name, worker bounds and idle timeout.
#
# Usage: rp serverless list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N        return at most N endpoints
#   --cursor <c>     offset to resume from; pairs with --limit
#   --jq <filter>    jq filter applied to the array
#   --json           print the raw API response
#
# Notes:
#   The table shows the configured worker min/max and idle timeout; live worker
#   counts come from `rp serverless workers <id>`.
#
# API: GET /v2/serverless

# doc: get
# Show one endpoint's full record and scaling config.
#
# Usage: rp serverless get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --jq <filter>    jq filter applied to the record
#   --json           print the raw API response instead of pretty JSON
#
# API: GET /v2/serverless/{id}

# doc: update
# Change an endpoint's workers, GPU pool, registry, template, name, or scaling.
#
# Usage: rp serverless update <id> [--workers-min N] [--workers-max N]
#                            [--idle S] [--gpu <types>] [--gpu-count N]
#                            [--registry <id>] [--template-id <id>]
#                            [--name <n>] [--scale-by delay|requests]
#                            [--scale-threshold N] [--scaler-type QUEUE_DELAY|REQUEST_COUNT]
#                            [--scaler-value V]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --workers-min N  new minimum worker count
#   --workers-max N  new maximum worker count
#   --idle S         workers.idleTimeout (ignored with REQUEST_COUNT scaling)
#   --gpu <types>    GPU type ids for the worker pool (alias: --gpu-id)
#   --gpu-count N    GPUs per worker (default: 1)
#   --registry <id>  registry credential for a private image (alias: --registry-auth-id)
#   --template-id <id>   swap the endpoint's template (PATCH field templateId;
#                        the API applies the template's container config)
#   --name <n>           rename the endpoint (PATCH field name)
#   --scale-by delay|requests   runpodctl coercion: maps to --scaler-type
#                               (delay→QUEUE_DELAY, requests→REQUEST_COUNT)
#   --scale-threshold N  runpodctl coercion: maps to --scaler-value (the
#                        queueDelay seconds, or requestCount)
#   --scaler-type QUEUE_DELAY|REQUEST_COUNT   scaling policy (rp native flag)
#   --scaler-value V      scaling threshold (rp native flag)
#   --json           print the raw API response
#
# Notes:
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty PATCH.
#   A --gpu change re-resolves pool ids from the type names.
#   --scale-by / --scale-threshold are coercion aliases (runpodctl spelling)
#   that feed the same scaling object as rp's --scaler-type / --scaler-value.
#
# API: PATCH /v2/serverless/{id}

# doc: delete
# Delete a serverless endpoint permanently.
#
# Usage: rp serverless delete <id>
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Notes:
#   Deletion is irreversible; any scaled workers are torn down with it.
#
# API: DELETE /v2/serverless/{id}

# doc: scale
# Set an endpoint's worker bounds and idle timeout in one call.
#
# Usage: rp serverless scale <id> --min N --max N [--idle S]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --min N          minimum worker count
#   --max N          maximum worker count
#   --idle S         workers.idleTimeout (ignored with REQUEST_COUNT scaling)
#   --json           print the raw API response
#
# Notes:
#   At least one of --min/--max/--idle is required.
#
# API: PATCH /v2/serverless/{id}

# doc: workers
# Show an endpoint's live workers: ids, states, placement, versions.
#
# Usage: rp serverless workers <id> [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --json           print the raw envelope (workers + summary + endpointVersion)
#
# Notes:
#   Human mode prints a status histogram (total/running/idle/init/throttled/
#   unhealthy) on stderr, then tables the active workers.
#
# API: GET /v2/serverless/{id}/workers

# doc: releases
# Show an endpoint's release history and rollout.
#
# Usage: rp serverless releases <id> [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --json           print the raw envelope (releases + rollout + endpointVersion)
#
# Notes:
#   Human mode prints the rollout summary (workers on latest / total, percent)
#   on stderr, then tables the releases with a per-release field diff.
#
# API: GET /v2/serverless/{id}/releases

# doc: logs
# Stream one worker's container and system logs live.
#
# Usage: rp serverless logs <id> --worker <workerId>
#                     [--source container|system] [--tail N]
#                     [--since <rfc3339>] [--last-event-id <ts>]
#
# Arguments:
#   <id>                      endpoint id — from `rp serverless list`
#
# Options:
#   --worker <workerId>       worker id (from `rp serverless workers <id>`);
#                             required
#   --source container|system restrict the stream; omit for both
#   --tail N                  historical lines to backfill (default: 100,
#                             maximum 5000); 0 streams live with no backfill
#   --since <rfc3339>         resume from a timestamp instead of backfilling
#   --last-event-id <ts>      SSE reconnect cursor emitted by this endpoint
#
# Notes:
#   The stream is Server-Sent Events written raw to stdout (no --json); Ctrl-C
#   ends it. The three resume flags follow --last-event-id > --since > --tail
#   precedence.
#   container is the worker's stdout/stderr; system is the host lifecycle log.
#
# API: GET /v2/serverless/{id}/workers/{workerId}/logs

# doc: run
# Submit a job to a deployed endpoint on the data plane.
#
# Usage: rp serverless run <id> --input '<json>' | --input-file <path|->
#                     [--sync|--async] [--worker-id <id>]
#                     [--affinity soft|strict|strict-resume] [--timeout <s>] [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --input '<json>'          job input as a JSON string
#   --input-file <path|->     read job input from a file, or - for stdin
#   --sync                    block until the job completes (default)
#   --async                   queue and print the job id instead of waiting
#   --worker-id <id>          pin the job to one worker on a load-balanced
#                             endpoint (X-Runpod-Worker-Id request header);
#                             ids come from `rp serverless workers <id>` or
#                             the response header of a previous run
#   --affinity soft|strict|strict-resume
#                             affinity mode for --worker-id (default: soft)
#   --timeout <s>             request timeout in seconds (default: 300)
#   --json                    print the raw API response
#
# Notes:
#   --input and --input-file are mutually exclusive, as are --sync and --async.
#   The body is wrapped as { "input": <json> } and POSTed to the endpoint's
#   runsync (or run, with --async) route on the data plane.
#   --worker-id/--affinity apply to load-balanced endpoints and compose with
#   --sync/--async alike. The header value is "[mode ]<id>": soft sends the
#   bare id (best-effort — the job falls back to normal selection when the
#   worker is unavailable; there is no literal "soft" token), strict sends
#   "strict <id>" (only that worker; the request waits up to ~5 minutes and
#   answers 400 `worker_timeout` on timeout, 404 `affinity_worker_gone` when
#   the worker is gone), strict-resume sends "strict-resume <id>" (strict,
#   plus it resumes a scaled-down worker before routing).
#   --affinity without --worker-id is a usage error.
#   Every load-balancer response also carries X-Runpod-Worker-Id; human mode
#   prints it ("served by worker: …") so the next request can be pinned.
#   Release the pin when done by omitting --worker-id, so the worker can go
#   idle.
#
# Examples:
# # Run a synchronous job with inline input
# $ rp serverless run end_abc --input '{"prompt":"hi"}'
# # Submit a job from a file and return immediately
# $ rp serverless run end_abc --input-file job.json --async
# # Pin a session to one worker (strict), then release the pin
# $ rp serverless run end_abc --input '{"prompt":"hi"}' --worker-id pod-abc123 --affinity strict
#
# API: POST /v2/{id}/runsync  (or /run with --async)

# doc: status
# Check the status of a job submitted earlier on a deployed endpoint.
#
# Usage: rp serverless status <id> <jobId> [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#   <jobId>          job id returned by `rp serverless run --async`
#
# Options:
#   --json           print the raw job-status envelope
#
# Notes:
#   The call rides the data plane (api.runpod.ai/v2), distinct from the
#   control-plane REST. stdout is the job payload (pretty in human mode), so a
#   FAILED job's `error` is still visible. Exit code mirrors runpodctl:
#   0 when the job is COMPLETED (and while it is IN_QUEUE / IN_PROGRESS),
#   1 when the job ends FAILED / CANCELLED / TIMED_OUT.
#
# Examples:
# # Check the status of one job
# $ rp serverless status end_abc job-60902e6c-0a1
#
# API: GET /{id}/status/{jobId}

# doc: health
# Show a deployed endpoint's operational health: worker and job counts.
#
# Usage: rp serverless health <id> [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --json           print the raw health envelope (workers + jobs)
#
# Notes:
#   The call rides the data plane (api.runpod.ai/v2), distinct from the
#   control-plane REST. Human mode prints a worker/job histogram to stdout.
#
# Examples:
# # Ping an endpoint's health
# $ rp serverless health end_abc
#
# API: GET /{id}/health

# ---------------------------------------------------------------------------
# Batch sub-resource (BETA): endpoint-scoped bulk inference on the control
# plane. Every batch is addressed by id; work starts only after an explicit
# finalize; completion is inferred when completed + failed equals the total.

### :::: documentation (rp doc serverless batch) :::: #############################

# doc: batch
# Submit large sets of inference requests to an endpoint as one managed batch (beta).
#
# Usage: rp serverless batch <verb> [flags]
#
# Notes:
#   A batch is endpoint-scoped and rides the control plane (unlike `run`,
#   which targets the data plane). Lifecycle: DRAFT → FINALIZED →
#   FAILED|CANCELLED — work starts only after `finalize`, there is no
#   RUNNING/COMPLETED status, and completion is inferred when completed +
#   failed counts equal the total. Batch workers are isolated from /run
#   traffic, so a batch never delays interactive jobs. Batches are addressed
#   by id (display names are not unique). Sub-verbs: list, create, add,
#   remove, finalize, cancel, get, requests, update.
#
# API: /v2/{endpoint_id}/batch

# doc: batch list
# List an endpoint's batches, newest first (beta).
#
# Usage: rp serverless batch list <endpoint> [--json]
#
# Arguments:
#   <endpoint>       endpoint id — from `rp serverless list`
#
# Options:
#   --json           print the raw API response
#
# Notes:
#   The table shows each batch's id, name, status and request counts (total,
#   completed, failed, in flight). A batch that is still processing reports
#   FINALIZED — there is no RUNNING or COMPLETED status.
#
# API: GET /v2/{endpoint_id}/batch

# doc: batch create
# Create a new DRAFT batch (beta).
#
# Usage: rp serverless batch create <endpoint> [--input '<json>']… [--input-file <path|->] [--json]
#
# Arguments:
#   <endpoint>       endpoint id — from `rp serverless list`
#
# Options:
#   --input '<json>' one request's input object; repeatable, each occurrence
#                    appends one request (must be a single JSON value)
#   --input-file <path|->
#                    a JSON array of input objects; `-` reads stdin. Combined
#                    with --input, file items come first
#   --json           print the raw API response
#
# Notes:
#   The request body is a top-level JSON array; without --input/--input-file an
#   empty array is sent. The new batch id is printed on stdout (confirmation on
#   stderr), so the id composes into add/finalize. The batch stays DRAFT —
#   nothing processes until `batch finalize`.
#
# Examples:
# # Create a batch with two requests
# $ rp serverless batch create end_abc --input '{"text":"a"}' --input '{"text":"b"}'
#
# API: POST /v2/{endpoint_id}/batch

# doc: batch add
# Append requests to a DRAFT batch (beta).
#
# Usage: rp serverless batch add <endpoint> <batchId> [--input '<json>']… [--input-file <path|->]
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id — printed by `batch create`
#
# Options:
#   --input '<json>' one request's input object; repeatable
#   --input-file <path|->
#                    a JSON array of input objects; `-` reads stdin; items
#                    precede --input values in the envelope
#
# Notes:
#   The API wraps the array as {"requests":[…]} and caps one call at 10 MiB —
#   oversized payloads are rejected locally before the POST; split them across
#   multiple add calls (each add is a visible billing/progress boundary, so the
#   CLI never chunks silently). Only DRAFT batches accept requests.
#
# API: POST /v2/{endpoint_id}/batch/{batch_id}/requests

# doc: batch remove
# Remove one request from a DRAFT batch (beta).
#
# Usage: rp serverless batch remove <endpoint> <batchId> <requestId>
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#   <requestId>      child request id — from `batch requests`
#
# Notes:
#   Only DRAFT batches accept removals; after finalize the request set is
#   locked.
#
# API: DELETE /v2/{endpoint_id}/batch/{batch_id}/requests/{request_id}

# doc: batch finalize
# Lock a DRAFT batch and make it eligible for execution (beta).
#
# Usage: rp serverless batch finalize <endpoint> <batchId>
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#
# Notes:
#   Finalize is the only door to execution — a DRAFT batch never processes.
#   After it, requests can no longer be added or removed; the batch stays
#   FINALIZED while it works.
#
# API: POST /v2/{endpoint_id}/batch/{batch_id}/finalize

# doc: batch cancel
# Cancel a batch (beta).
#
# Usage: rp serverless batch cancel <endpoint> <batchId>
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#
# Notes:
#   Queued requests are cancelled immediately and are not billed; in-flight
#   requests finish and bill normally. The batch reaches CANCELLED once the
#   in-flight work has drained. No confirmation prompt (house style).
#
# API: POST /v2/{endpoint_id}/batch/{batch_id}/cancel

# doc: batch get
# Show a batch's progress summary (beta).
#
# Usage: rp serverless batch get <endpoint> <batchId> [--wait] [--interval <s>] [--timeout <s>] [--json]
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#
# Options:
#   --wait           poll until the counts reconcile (completed + failed =
#                    total) or the batch reaches a terminal state
#   --interval <s>   seconds between polls (default 5)
#   --timeout <s>    cap the wait (default: none — batches are multi-hour by
#                    design; Ctrl-C or this flag ends the wait)
#   --json           print the raw API response
#
# Notes:
#   The API has no RUNNING/COMPLETED status: progress is the counts. With
#   --wait, headlines print to stderr only when the done-count changes, so
#   --json stdout and pipes stay clean. Exit code: 0 on completion regardless
#   of how many child requests failed (failures are data — see `batch
#   requests`); 1 when the batch itself reaches FAILED or CANCELLED; non-zero
#   when --timeout expires.
#
# Examples:
# # Wait for a batch to finish, checking every 30s
# $ rp serverless batch get end_abc b_01j9abc --wait --interval 30
#
# API: GET /v2/{endpoint_id}/batch/{batch_id}

# doc: batch requests
# List a batch's child requests with per-request status and results (beta).
#
# Usage: rp serverless batch requests <endpoint> <batchId> [--status completed|failed|in-progress|queued] [--limit N] [--cursor N] [--json]
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#
# Options:
#   --status <s>     client-side filter (completed|failed|in-progress|queued);
#                    --status completed is the results view
#   --limit <n>      page size (server-side)
#   --cursor <n>     server-side offset for the next page
#   --json           print the raw paginated envelope (incl. total/hasMore)
#
# Notes:
#   Pagination is server-side (offset/limit); each child carries a status and
#   either an output or an error message from the handler. A failed child does
#   not fail the batch.
#
# API: GET /v2/{endpoint_id}/batch/{batch_id}/requests

# doc: batch update
# Rename a batch (beta).
#
# Usage: rp serverless batch update <endpoint> <batchId> --name <n>
#
# Arguments:
#   <endpoint>       endpoint id
#   <batchId>        batch id
#
# Options:
#   --name <n>       new display name (required)
#
# Notes:
#   The name is a display label only; batches are always addressed by id.
#
# API: PUT /v2/{endpoint_id}/batch/{batch_id}

# Table of an endpoint's batches, newest first; --json passes the raw envelope.
_serverless_batch_list() {
  local ep
  rp::require_pos ep "usage: rp serverless batch list <endpoint> [--json]"
  rp::require_id ep "$ep" "endpoint id"
  local body
  body="$(rp::http GET "/serverless/$ep/batch")"
  local arr
  arr="$(rp::unwrap batches "$body")"
  rp::emit_json_or "$body" rp::table "$arr" --reshape \
    'map({id, name, status,
          total:(.requestTotal // 0), completed:(.requestCompleted // 0),
          failed:(.requestFailed // 0), running:(.requestInProgress // 0)})' \
    id name status total completed failed running
}

# Assemble the batch request array from --input-file (a JSON array of inputs;
# `-` reads stdin) and repeatable --input values — file items first, then flag
# values. Assigns the top-level JSON array of {"input":…} objects to the
# nameref in $1. Runs in the main shell so rp::usage exits the caller; never
# call it inside command substitution. The add verb wraps the array into the
# API's {"requests":[…]} envelope; create POSTs it bare.
_serverless_batch_inputs() {
  local -n inputs_out="$1"
  local file input items line wrapped
  file="$(rp::args_get input-file)"
  input="$(rp::args_get input)"
  items="[]"
  if [[ -n "$file" ]]; then
    if [[ "$file" == - ]]; then
      items="$(cat)"
    else
      [[ -r "$file" ]] || rp::usage "cannot read --input-file '$file'"
      items="$(<"$file")"
    fi
    printf '%s' "$items" | jq -e 'type == "array"' >/dev/null 2>&1 ||
      rp::usage "--input-file must hold a JSON array of request inputs"
    items="$(printf '%s' "$items" | jq -c 'map({input: .})')" ||
      rp::usage "--input-file is not valid JSON"
  fi
  local extra="[]"
  local -a elems=()
  if [[ -n "$input" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      wrapped="$(printf '%s' "$line" | jq -c '{input: .}' 2>/dev/null)" ||
        rp::usage "--input is not valid JSON: $line"
      elems+=("$wrapped")
    done <<<"$input"
    if ((${#elems[@]})); then
      extra="$(printf '%s\n' "${elems[@]}" | jq -sc .)"
    fi
  fi
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  inputs_out="$(printf '%s %s' "$items" "$extra" | jq -sc '.[0] + .[1]')" ||
    rp::usage "could not assemble batch requests from --input-file/--input"
}

# Create a new DRAFT batch on an endpoint. The request body is a top-level JSON
# array (empty without --input/--input-file). Prints the new batch id on stdout
# (confirmation on stderr), so `rp serverless batch create e1 …` composes into
# add/finalize.
_serverless_batch_create() {
  local ep
  rp::require_pos ep "usage: rp serverless batch create <endpoint> [--input '<json>']… [--input-file <path|->] [--json]"
  rp::require_id ep "$ep" "endpoint id"
  local body
  _serverless_batch_inputs body
  local res id
  res="$(rp::http POST "/serverless/$ep/batch" "$body")"
  id="$(printf '%s' "$res" | jq -r '.id // empty')"
  [[ -n "$id" ]] || rp::die "batch create returned no id: $res"
  rp::ok "created batch: $id (DRAFT — finalize to start processing)"
  printf '%s\n' "$id"
}

# Append requests to a DRAFT batch. The API wraps the array as
# {"requests":[…]} and caps one call at RP_BATCH_APPEND_MAX — the guard fires
# before the POST so an oversized batch is split by the user (each add is a
# visible billing/progress boundary), never silently chunked.
_serverless_batch_add() {
  local ep batch
  rp::require_pos ep "usage: rp serverless batch add <endpoint> <batchId> [--input '<json>']… [--input-file <path|->]"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_pos_at 1 batch "usage: rp serverless batch add <endpoint> <batchId> [--input '<json>']… [--input-file <path|->]"
  rp::require_id batch "$batch" "batch id"
  local arr
  _serverless_batch_inputs arr
  local body
  body="$(printf '%s' "$arr" | jq -c '{requests: .}')" || rp::usage "could not wrap batch requests"
  local size
  size="$(printf '%s' "$body" | wc -c | tr -d ' ')"
  ((size <= RP_BATCH_APPEND_MAX)) ||
    rp::usage "batch request payload is $((size / 1048576)) MiB — the API caps one add call at 10 MiB; split into multiple 'rp serverless batch add' calls"
  local res
  res="$(rp::http POST "/serverless/$ep/batch/$batch/requests" "$body")"
  local added
  added="$(printf '%s' "$res" | jq -r '.added // empty')"
  rp::ok "added ${added:-} request(s) to batch $batch"
}

# Shared tail for the single-batch mutation verbs: both positionals, POST a
# sub-path, confirm on stderr. Finalize locks a DRAFT batch (the only door to
# execution); cancel drops queued requests unbilled and lets in-flight drain.
_serverless_batch_simple_post() {
  local ep batch path label
  ep="${1}" batch="${2}" path="${3}" label="${4}"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_id batch "$batch" "batch id"
  rp::http POST "/serverless/$ep/batch/$batch/$path" '{}' >/dev/null
  rp::ok "$label batch $batch"
}

_serverless_batch_finalize() {
  local ep batch
  rp::require_pos ep "usage: rp serverless batch finalize <endpoint> <batchId>"
  rp::require_pos_at 1 batch "usage: rp serverless batch finalize <endpoint> <batchId>"
  _serverless_batch_simple_post "$ep" "$batch" "finalize" "finalized"
}

_serverless_batch_cancel() {
  local ep batch
  rp::require_pos ep "usage: rp serverless batch cancel <endpoint> <batchId>"
  rp::require_pos_at 1 batch "usage: rp serverless batch cancel <endpoint> <batchId>"
  _serverless_batch_simple_post "$ep" "$batch" "cancel" "cancelled"
}

# Remove one child request from a DRAFT batch (impossible after finalize).
_serverless_batch_remove() {
  local ep batch req
  rp::require_pos ep "usage: rp serverless batch remove <endpoint> <batchId> <requestId>"
  rp::require_pos_at 1 batch "usage: rp serverless batch remove <endpoint> <batchId> <requestId>"
  rp::require_pos_at 2 req "usage: rp serverless batch remove <endpoint> <batchId> <requestId>"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_id batch "$batch" "batch id"
  rp::require_id req "$req" "request id"
  rp::http DELETE "/serverless/$ep/batch/$batch/requests/$req" '{}' >/dev/null
  rp::ok "removed request $req from batch $batch"
}

# One-shot or --wait batch summary. The API has no RUNNING/COMPLETED status —
# progress is the counts, and the batch is finished when completed + failed
# equals total. Human mode: headline on stderr; --json: raw envelope on stdout.
# --wait owns the fetching (one GET per poll); the final headline is the last
# progress line, so it is not printed twice.
_serverless_batch_get() {
  local ep batch
  rp::require_pos ep "usage: rp serverless batch get <endpoint> <batchId> [--wait] [--interval <s>] [--timeout <s>] [--json]"
  rp::require_pos_at 1 batch "usage: rp serverless batch get <endpoint> <batchId> [--wait] [--interval <s>] [--timeout <s>] [--json]"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_id batch "$batch" "batch id"
  local body
  if rp::args_has wait; then
    local wrc=0
    _serverless_batch_poll "$ep" "$batch" body || wrc=$?
    rp::args_has json && printf '%s\n' "$body"
    return "$wrc"
  fi
  body="$(rp::http GET "/serverless/$ep/batch/$batch")"
  rp::emit_json_or "$body" _serverless_batch_headline "$body"
}

# Poll a batch until its counts reconcile (or a terminal state arrives).
# Progress headlines go to stderr only when the done-count changes, so --json
# stdout and pipes stay clean. No default cap — batches are multi-hour by
# design; --timeout <s> adds one, and expiry dies non-zero. The exit mapping
# is the command's: 0 on completion (request failures are data, not failure),
# 1 on batch-level FAILED/CANCELLED.
_serverless_batch_poll() {
  local ep="$1" batch="$2"
  local -n poll_body="$3"
  local interval timeout deadline last_done=-1 done_now
  interval="$(rp::args_get_uint interval 5)"
  timeout="$(rp::args_get_uint timeout)"
  deadline=0
  ((timeout > 0)) && deadline=$((SECONDS + timeout))
  while :; do
    poll_body="$(rp::http GET "/serverless/$ep/batch/$batch")"
    done_now="$(printf '%s' "$poll_body" | jq -r '((.requestCompleted // 0) + (.requestFailed // 0))')"
    [[ "$done_now" != "$last_done" ]] && {
      _serverless_batch_headline "$poll_body"
      last_done="$done_now"
    }
    if [[ "$(printf '%s' "$poll_body" | jq -r '.status // ""')" == FAILED || "$(printf '%s' "$poll_body" | jq -r '.status // ""')" == CANCELLED ]]; then
      return 1
    fi
    printf '%s' "$poll_body" | jq -e '((.requestCompleted // 0) + (.requestFailed // 0)) >= (.requestTotal // 0)' >/dev/null && return 0
    ((deadline > 0)) && ((SECONDS >= deadline)) &&
      rp::die "wait timed out after ${timeout}s — batch still processing (rerun the same command to resume)"
    ((interval > 0)) && sleep "$interval"
  done
}

_serverless_batch_headline() {
  rp::info "$(printf '%s' "$1" | jq -r '"batch \(.id // "?") [\(.status // "?")]  done=\(.requestCompleted // 0)/\(.requestTotal // 0) inFlight=\(.requestInProgress // 0) failed=\(.requestFailed // 0)"')"
}

# Paginated child-request listing. Pagination is SERVER-side here (offset/limit
# query params), so --limit/--cursor forward to the API — the contract
# lib/paginate.sh names for when server pagination lands. --status filters
# client-side (the API documents no status param): --status completed is the
# "give me my results" view.
_serverless_batch_requests() {
  local ep batch status q
  rp::require_pos ep "usage: rp serverless batch requests <endpoint> <batchId> [--status completed|failed|in-progress|queued] [--limit N] [--cursor N] [--json]"
  rp::require_pos_at 1 batch "usage: rp serverless batch requests <endpoint> <batchId> [--status completed|failed|in-progress|queued] [--limit N] [--cursor N] [--json]"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_id batch "$batch" "batch id"
  local limit cursor
  limit="$(rp::args_get_uint limit)"
  cursor="$(rp::args_get_uint cursor)"
  q="$(rp::query_params offset "$cursor" limit "$limit")"
  status="$(rp::args_get status)"
  case "$status" in
  '' | completed | failed | in-progress | queued) ;;
  *) rp::usage "invalid --status '$status' (expected completed|failed|in-progress|queued)" ;;
  esac
  local body
  body="$(rp::http GET "/serverless/$ep/batch/$batch/requests$q")"
  if ! rp::args_has json; then
    local arr
    arr="$(rp::unwrap requests "$body")"
    [[ -n "$status" ]] &&
      arr="$(printf '%s' "$arr" | jq -c --arg s "$status" 'map(select(.status == ($s | ascii_upcase | sub("-", "_"; "g"))))')"
    rp::table "$arr" id status error
    return
  fi
  printf '%s\n' "$body"
}

# Update batch attributes — display name only today (the cluster-rename
# precedent: single mutable field, verb reads as rename).
_serverless_batch_update() {
  local ep batch name
  rp::require_pos ep "usage: rp serverless batch update <endpoint> <batchId> --name <n>"
  rp::require_pos_at 1 batch "usage: rp serverless batch update <endpoint> <batchId> --name <n>"
  rp::require_id ep "$ep" "endpoint id"
  rp::require_id batch "$batch" "batch id"
  name="$(rp::args_get name)"
  [[ -n "$name" ]] || rp::usage "rp serverless batch update needs --name <n>"
  local obj res
  obj="$(jq -cn --arg name "$name" '{name: $name}')"
  res="$(rp::http PUT "/serverless/$ep/batch/$batch" "$obj")"
  rp::ok "renamed batch $batch to '$name'"
}

rp::cmd_serverless() {
  local verb="${1:-help}"
  shift || true
  if [[ "$verb" == "batch" ]]; then
    _serverless_batch "$@"
    return
  fi
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _serverless_create ;;
  list) rp::resource_list serverless --reshape 'map({id, name, workersMin:.workers.min, workersMax:.workers.max, idleTimeout:.workers.idleTimeout})' id name workersMin workersMax idleTimeout ;;
  get) rp::resource_get serverless ;;
  update) _serverless_update ;;
  delete) rp::resource_delete serverless ;;
  scale) _serverless_scale ;;
  workers) _serverless_workers ;;
  releases) _serverless_releases ;;
  logs) _serverless_logs ;;
  run) _serverless_run ;;
  status) _serverless_status ;;
  health) _serverless_health ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp serverless <verb> [flags]
   create --template <id>|--template-id <id> [--name <n>] [--gpu <type,..> (alias: --gpu-id) | --gpus-from-volume <name>] [--network-volume <name> | --network-volume-id <id> | --network-volume-ids <id,id>]
           [--type QUEUE|LOAD_BALANCER] [--workers-min N] [--workers-max N] [--idle S] [--gpu-count N] [--flashboot]
           [--env K=V]…  (--env is repeatable K=V; NOT aliased to runpodctl's JSON --env)
           [--scaler-type QUEUE_DELAY|REQUEST_COUNT] [--scaler-value V] [--execution-timeout <s>] [--hub-id <listing-id>] [--force] [--registry <id> (alias: --registry-auth-id)]
           (idempotent by --name; --hub-id deploys from a Hub listing; --type defaults to QUEUE;
            --scaler-type defaults to QUEUE_DELAY with queueDelay 4; --idle sets workers.idleTimeout;
            --env overlays the template's env, user value winning per key)
   list | get <id> | update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <types> (alias: --gpu-id)] [--gpu-count N] [--registry <id> (alias: --registry-auth-id)] [--template-id <id>] [--name <n>]
           [--scale-by delay|requests (runpodctl coercion: --scaler-type)] [--scale-threshold N (runpodctl coercion: --scaler-value)]
           [--scaler-type QUEUE_DELAY|REQUEST_COUNT] [--scaler-value V] | scale <id> --min N --max N [--idle S] | delete <id>
   run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--worker-id <id>] [--affinity soft|strict|strict-resume] [--timeout <s>] [--json]
              (--worker-id pins the job to one worker on a load-balanced endpoint via X-Runpod-Worker-Id;
               bare id = soft affinity, strict/strict-resume prefix the id; human mode prints the
               "served by worker" response stamp so the next request can be pinned)
  workers <id>        live worker ids/states/placement (+ status histogram, --json for full envelope)
  releases <id>       release history newest-first (+ rollout summary; per-release diff column)
  logs <id> --worker <id>   live worker log stream (--worker id from `workers`; same source/tail/since/last-event-id flags)
   status <id> <jobId>     data-plane job status: GET /{id}/status/{jobId} (exit 0 COMPLETED, 1 FAILED|CANCELLED|TIMED_OUT)
   health <id>          data-plane health: GET /{id}/health (worker + job counts; --json for full envelope)
   batch <verb> <…>     endpoint-scoped bulk inference (beta): rp serverless batch --help
EOF
    ;;
  *) rp::usage "unknown serverless verb: '$verb'" ;;
  esac
}

# Sub-resource dispatcher: `rp serverless batch <verb> [args]`. Explicit verbs
# only — a bare `rp serverless batch` prints the verb help, mirroring
# `registry delegations`.
_serverless_batch() {
  local sub="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && sub=help
  case "$sub" in
  list) _serverless_batch_list ;;
  create) _serverless_batch_create ;;
  add) _serverless_batch_add ;;
  finalize) _serverless_batch_finalize ;;
  cancel) _serverless_batch_cancel ;;
  remove) _serverless_batch_remove ;;
  get) _serverless_batch_get ;;
  requests) _serverless_batch_requests ;;
  update) _serverless_batch_update ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp serverless batch <verb> [flags]   (beta)
  list <endpoint>              batches for an endpoint, newest first (--json for raw)
  create <endpoint> [--input '<json>']… [--input-file <path|->]   new DRAFT batch (id on stdout)
  add <endpoint> <batchId> [--input '<json>']… [--input-file <path|->]   append requests (DRAFT only; 10 MiB per call)
  remove <endpoint> <batchId> <requestId>   drop one request (DRAFT only)
  finalize <endpoint> <batchId>   lock the batch — requests start processing only after this
  cancel <endpoint> <batchId>     drop queued (unbilled) requests; in-flight ones finish and bill
  requests <endpoint> <batchId> [--status completed|failed|in-progress|queued] [--limit N] [--cursor N]   child requests, server-paginated (--status completed = results view)
  update <endpoint> <batchId> --name <n>    rename a batch
EOF
    ;;
  *) rp::usage "unknown batch verb: '$sub' (see: rp serverless batch --help)" ;;
  esac
}
