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
    _out_type="$stype"
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

  local template
  template="$(rp::args_get template)"
  [[ -n "$template" ]] || rp::usage "usage: rp serverless create --template <id> [--name <n>] [--gpu <type,..>] [--force] … (see: rp serverless --help; idempotent by name)"
  [[ -n "$name" ]] || rp::usage "usage: rp serverless create --template <id> --name <n> [--gpu <type,..>] … (see: rp serverless --help; idempotent by name)"

  # Idempotency gate after the --template requirement but before GPU resolution:
  # the v2 --gpu check (and its catalogue lookups) would otherwise exit before
  # rp::resource_create's own gate could run on a re-run.
  if rp::resource_existing serverless "$name"; then
    return 0
  fi

  # v2 has no templateId param: spread the template's container config, then add
  # the endpoint-specific fields that the template does not carry (gpu, scaling…).
  local obj
  obj="$(rp::template_spread "$template")"

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
  rp::require_pos id "usage: rp serverless update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>] [--registry <id>]"
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
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update"
  local res
  res="$(rp::http PATCH "$RP_RES_PATH/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated endpoint $id"
}

# Submit a job to a deployed endpoint on the data plane (RP_API_BASE). Default
# is /runsync, which blocks until the job completes; --async queues via /run
# and prints the job id. The payload is wrapped through jq's stdin (never
# argv/--argjson) so a base64-heavy --input-file body stays out of `ps`.
_serverless_run_human() {
  local id="$1" body="$2"
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
  rp::require_pos id "usage: rp serverless run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--timeout <s>] [--json]"
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
  local route=runsync timeout
  rp::args_has async && route=run
  timeout="$(rp::args_get_uint timeout 300)"
  local body
  body="$(rp::http_api POST "/$id/$route" "$payload" "$timeout")"
  rp::emit_json_or "$body" _serverless_run_human "$id" "$body"
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
# Usage: rp serverless create --template <id> --name <n> [--gpu <type,..>]
#                             [--network-volume <name> | --network-volume-id <id>
#                              | --network-volume-ids <id,id>]
#                             [--type QUEUE|LOAD_BALANCER] [flags]
#
# Options:
#   --template <id>               template id to deploy (required unless --hub-id)
#   --hub-id <listing-id>         deploy from a Hub listing (requires --name;
#                                 mutually exclusive with --template)
#   --name <n>                    endpoint name (required); idempotent by name
#   --gpu <type,..>               GPU type ids (comma-separated) for the pool
#   --gpus-from-volume <name>     resolve in-stock GPU types from a network
#                                 volume's datacentre instead of --gpu
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
#                                 the template's env on the --template path
#   --scaler-type QUEUE_DELAY|REQUEST_COUNT   scaling policy
#   --scaler-value V              scaling threshold (default: 4s / 1 request)
#   --execution-timeout <s>       per-job timeout, sent as milliseconds
#   --registry <id>               registry credential for a private image
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
#   rp serverless create --name ocr --template tmpl_abc --gpu "NVIDIA L4"
#   rp serverless create --name diff --hub-id hub_xyz --gpu "NVIDIA A40"
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
# Change an endpoint's workers, GPU pool, or registry credential.
#
# Usage: rp serverless update <id> [--workers-min N] [--workers-max N]
#                            [--idle S] [--gpu <types>] [--gpu-count N]
#                            [--registry <id>]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --workers-min N  new minimum worker count
#   --workers-max N  new maximum worker count
#   --idle S         workers.idleTimeout (ignored with REQUEST_COUNT scaling)
#   --gpu <types>    GPU type ids for the worker pool
#   --gpu-count N    GPUs per worker (default: 1)
#   --registry <id>  registry credential for a private image
#   --json           print the raw API response
#
# Notes:
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty PATCH.
#   A --gpu change re-resolves pool ids from the type names.
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
#                     [--sync|--async] [--timeout <s>] [--json]
#
# Arguments:
#   <id>             endpoint id — from `rp serverless list`
#
# Options:
#   --input '<json>'          job input as a JSON string
#   --input-file <path|->     read job input from a file, or - for stdin
#   --sync                    block until the job completes (default)
#   --async                   queue and print the job id instead of waiting
#   --timeout <s>             request timeout in seconds (default: 300)
#   --json                    print the raw API response
#
# Notes:
#   --input and --input-file are mutually exclusive, as are --sync and --async.
#   The body is wrapped as { "input": <json> } and POSTed to the endpoint's
#   runsync (or run, with --async) route on the data plane.
#
# Examples:
#   rp serverless run end_abc --input '{"prompt":"hi"}'
#   rp serverless run end_abc --input-file job.json --async
#
# API: POST /v2/{id}/runsync  (or /run with --async)

rp::cmd_serverless() {
  local verb="${1:-help}"
  shift || true
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
  -h | --help | help)
    cat <<'EOF'
Usage: rp serverless <verb> [flags]
  create --template <id> [--name <n>] [--gpu <type,..> | --gpus-from-volume <name>] [--network-volume <name> | --network-volume-id <id> | --network-volume-ids <id,id>]
          [--type QUEUE|LOAD_BALANCER] [--workers-min N] [--workers-max N] [--idle S] [--gpu-count N] [--flashboot] [--env K=V]…
          [--scaler-type QUEUE_DELAY|REQUEST_COUNT] [--scaler-value V] [--execution-timeout <s>] [--hub-id <listing-id>] [--force] [--registry <id>]
          (idempotent by --name; --hub-id deploys from a Hub listing; --type defaults to QUEUE;
           --scaler-type defaults to QUEUE_DELAY with queueDelay 4; --idle sets workers.idleTimeout;
           --env overlays the template's env, user value winning per key)
  list | get <id> | update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <types>] [--gpu-count N] [--registry <id>] | scale <id> --min N --max N [--idle S] | delete <id>
  run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--timeout <s>] [--json]
  workers <id>        live worker ids/states/placement (+ status histogram, --json for full envelope)
  releases <id>       release history newest-first (+ rollout summary; per-release diff column)
  logs <id> --worker <id>   live worker log stream (--worker id from `workers`; same source/tail/since/last-event-id flags)
EOF
    ;;
  *) rp::usage "unknown serverless verb: '$verb'" ;;
  esac
}
