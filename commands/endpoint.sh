#!/usr/bin/env bash
# `rp endpoint` — serverless endpoint CRUD plus Hub-listing deploy (saveEndpoint
# replaced by POST /v2/serverless in API v2).
RP_DEFAULT_GPUS=(
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
  wantjson="$(rp::json_array "${RP_DEFAULT_GPUS[@]}")"
  rp::http GET '/catalog/gpus?include=AVAILABILITY&product=SERVERLESS' | rp::unwrap gpus | jq -r --argjson want "$wantjson" '
    map(select(.availability != null and .availability != "NONE"))
    | map(select(.id as $id | $want | index($id)))
    | map(.id) | .[]'
}

# Map a GPU-type CSV to a serverless pool-id CSV, dying with the standard message
# when no pool covers a given type. Centralises the get → validate pair that the
# create/update paths would otherwise repeat (and, in the update path, skip — which
# silently sent an empty pool list instead of erroring).
_endpoint_gpu_poolcsv() {
  local gpu="$1" poolcsv
  poolcsv="$(rp::gpu_type_to_pool_csv "$gpu")"
  [[ -n "$poolcsv" ]] || rp::usage "could not map GPU types to serverless pool ids: $gpu"
  printf '%s' "$poolcsv"
}

# Resolve --network-volume / --network-volume-id to the volume id and
# datacenter, setting the caller's `nvid` and `dc` locals (name → id via
# rp::volume_dc, id → dc via rp::volume_dc_id).
_endpoint_resolve_nv() {
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

_endpoint_create() {
  local name
  name="$(rp::args_get name)"
  local hubid
  hubid="$(rp::args_get hub-id)"
  if [[ -n "$hubid" ]]; then
    [[ -z "$(rp::args_get template)" ]] || rp::usage "--hub-id and --template are mutually exclusive"
    _endpoint_create_hub "$hubid"
    return $?
  fi
  local template
  template="$(rp::args_get template)"
  [[ -n "$template" ]] || rp::usage "usage: rp endpoint create --template <id> [--name <n>] [--gpu <type,..>] [--force] … (see: rp endpoint --help; idempotent by name)"

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
  _endpoint_resolve_nv
  if [[ -n "$dc" ]]; then
    rp::obj_set obj dataCenterIds "$(rp::json_array "$dc")"
    rp::info "endpoint scoped to NV datacenter: $dc"
    [[ -n "$gpusfrom" ]] && gpu="$(_resolve_gpus_from_volume "$gpusfrom" | paste -sd, -)"
  fi
  if [[ -n "$gpu" ]]; then
    poolcsv="$(_endpoint_gpu_poolcsv "$gpu")"
  fi
  if [[ -z "$poolcsv" ]]; then
    rp::usage "rp endpoint create requires --gpu <type,..> (or --gpus-from-volume) in API v2"
  fi
  local count
  count="$(rp::args_get_uint gpu-count 1)"
  rp::obj_set obj gpu "$(rp::json_gpu_endpoint "$poolcsv" "$count")"

  local wmin wmax
  wmin="$(rp::args_get_uint workers-min)"
  wmax="$(rp::args_get_uint workers-max)"
  if [[ -n "$wmin" || -n "$wmax" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax")"
  fi

  local stype sval idle
  stype="$(rp::args_get scaler-type)"
  sval="$(rp::args_get scaler-value)"
  idle="$(rp::args_get_uint idle)"
  if [[ -n "$stype" || -n "$sval" || -n "$idle" ]]; then
    local scaling='{}'
    [[ -n "$stype" ]] && rp::obj_set scaling type "$(rp::json_str "$stype")"
    [[ -n "$sval" ]] && rp::obj_set scaling value "$sval"
    [[ -n "$idle" ]] && rp::obj_set scaling idleTimeout "$idle"
    rp::obj_set obj scaling "$scaling"
  fi

  # FlashBoot enum is OFF|FLASHBOOT|PRIORITY_FLASHBOOT in v2 ("ON" is rejected).
  rp::args_has flashboot && rp::obj_set obj flashboot "$(rp::json_str FLASHBOOT)"

  local mincuda execto
  mincuda="$(rp::args_get min-cuda-version)"
  if [[ -n "$mincuda" ]]; then
    rp::warn "note: --min-cuda-version has no v2 equivalent on create and was ignored (v2 keeps it only as a /catalog/gpus filter)"
  fi
  execto="$(rp::args_get_uint execution-timeout)"
  [[ -n "$execto" ]] && rp::obj_set obj timeout "$((execto * 1000))"

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

  local envcfg
  envcfg="$(rp::args_get env)"
  if [[ -n "$envcfg" ]]; then
    rp::warn "note: --env is ignored with --template (the template carries the container env; use --hub-id to set env)"
  fi

  rp::resource_create endpoint "$name" "$obj"
}

# Deploy straight from a Hub listing. The listing is still fetched via GraphQL
# (Hub has no API v2 endpoint), but the endpoint is created with POST /v2/serverless
# using GPU pool ids (saveEndpoint is gone in v2).
_endpoint_create_hub() {
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
    poolcsv="$(_endpoint_gpu_poolcsv "$gpu")"
  else
    poolcsv="$(printf '%s' "$cfg" | jq -r '.gpuIds // empty')"
    [[ -n "$poolcsv" ]] || rp::usage "listing '$hubid' declares no gpuIds — pass --gpu <type,..>"
  fi

  local gpucount cdisk
  gpucount="$(rp::args_get_uint gpu-count "$(printf '%s' "$cfg" | jq -r '.gpuCount // 1')")"
  cdisk="$(printf '%s' "$cfg" | jq -r '.containerDiskInGb // 20')"

  # v2 ContainerConfig.env is an object map {K:"V"}, not [{key,value}].
  local envuser envjson
  envuser="$(rp::args_get env)"
  if [[ -n "$envuser" ]]; then
    envjson="$(rp::env_to_json "$envuser")"
  else
    envjson="$(printf '%s' "$cfg" | jq -c '(.env // []) | map(select(.input.default != null) | {(.key): (.input.default|tostring)}) | add // {}')"
  fi

  local nvid dc=''
  _endpoint_resolve_nv
  if [[ -n "$dc" ]]; then
    rp::info "hub endpoint scoped to NV datacenter: $dc"
  fi

  local hwmin hwmax
  hwmin="$(rp::args_get_uint workers-min 0)"
  hwmax="$(rp::args_get_uint workers-max 0)"
  local body
  body="$(rp::json_obj \
    name "$(rp::json_str "$name")" \
    image "$(rp::json_str "$image")" \
    disk "$cdisk" \
    env "$envjson" \
    gpu "$(rp::json_gpu_endpoint "$poolcsv" "$gpucount")" \
    workers "$(rp::json_workers "$hwmin" "$hwmax")")"
  if [[ -n "$nvid" ]]; then
    body="$(_json_merge "$body" "$(rp::json_obj networkVolumes "$(rp::json_array "$nvid")" dataCenterIds "$(rp::json_array "$dc")")")"
  fi
  rp::resource_create endpoint "$name" "$body" "from hub listing $hubid"
}

_endpoint_scale() {
  local id
  rp::require_pos id "usage: rp endpoint scale <id> --min N --max N [--idle S]"
  local obj='{}' wmin wmax idle
  wmin="$(rp::args_get_uint min)"
  wmax="$(rp::args_get_uint max)"
  idle="$(rp::args_get_uint idle)"
  if [[ -n "$wmin" || -n "$wmax" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax")"
  fi
  [[ -n "$idle" ]] && rp::obj_set obj scaling "$(rp::json_obj idleTimeout "$idle")"
  [[ "$obj" != '{}' ]] || rp::usage "nothing to scale (pass --min/--max/--idle)"
  local res
  res="$(rp::http PATCH "/serverless/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "scaled endpoint $id"
}

_endpoint_update() {
  local id
  rp::require_pos id "usage: rp endpoint update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>]"
  local obj='{}' gpu
  local wmin wmax idle
  wmin="$(rp::args_get_uint workers-min)"
  wmax="$(rp::args_get_uint workers-max)"
  idle="$(rp::args_get_uint idle)"
  if [[ -n "$wmin" || -n "$wmax" ]]; then
    rp::obj_set obj workers "$(rp::json_workers "$wmin" "$wmax")"
  fi
  [[ -n "$idle" ]] && rp::obj_set obj scaling "$(rp::json_obj idleTimeout "$idle")"
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpu" ]]; then
    local poolcsv count
    poolcsv="$(_endpoint_gpu_poolcsv "$gpu")"
    count="$(rp::args_get_uint gpu-count 1)"
    rp::obj_set obj gpu "$(rp::json_gpu_endpoint "$poolcsv" "$count")"
  fi
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update"
  local res
  res="$(rp::http PATCH "/serverless/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated endpoint $id"
}

# Submit a job to a deployed endpoint on the data plane (RP_API_BASE). Default
# is /runsync, which blocks until the job completes; --async queues via /run
# and prints the job id. The payload is wrapped through jq's stdin (never
# argv/--argjson) so a base64-heavy --input-file body stays out of `ps`.
_endpoint_run_human() {
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

_endpoint_run() {
  local id
  rp::require_pos id "usage: rp endpoint run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--timeout <s>] [--json]"
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
  [[ -n "$input" ]] || rp::usage "rp endpoint run needs --input '<json>' or --input-file <path|->"
  local payload
  payload="$(printf '%s' "$input" | jq -c '{input: .}' 2>/dev/null)" || rp::usage "--input is not valid JSON"
  local route=runsync timeout
  rp::args_has async && route=run
  timeout="$(rp::args_get_uint timeout 300)"
  local body
  body="$(rp::http_api POST "/$id/$route" "$payload" "$timeout")"
  rp::emit_json_or "$body" _endpoint_run_human "$id" "$body"
}

rp::cmd_endpoint() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _endpoint_create ;;
  list) rp::resource_list endpoint --reshape 'map({id, name, workersMin:.workers.min, workersMax:.workers.max, idleTimeout:.scaling.idleTimeout})' id name workersMin workersMax idleTimeout ;;
  get) rp::resource_get endpoint ;;
  update) _endpoint_update ;;
  delete) rp::resource_delete endpoint ;;
  scale) _endpoint_scale ;;
  run) _endpoint_run ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp endpoint <verb> [flags]
  create --template <id> [--name <n>] [--gpu <type,..> | --gpus-from-volume <name>] [--network-volume <name> | --network-volume-id <id> | --network-volume-ids <id,id>]
          [--workers-min N] [--workers-max N] [--idle S] [--gpu-count N] [--flashboot]
          [--scaler-type T] [--scaler-value V] [--execution-timeout <s>] [--hub-id <listing-id>] [--force]
          (idempotent by --name; --hub-id deploys from a Hub listing)
  list | get <id> | update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <types>] [--gpu-count N] | scale <id> --min N --max N [--idle S] | delete <id>
  run <id> --input '<json>' | --input-file <path|-> [--sync|--async] [--timeout <s>] [--json]
EOF
    ;;
  *) rp::usage "unknown endpoint verb: '$verb'" ;;
  esac
}
