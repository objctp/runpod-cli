#!/usr/bin/env bash
# `rp endpoint` — serverless endpoint CRUD plus Hub-listing deploy via GraphQL saveEndpoint.
RP_DEFAULT_GPUS=(
  "NVIDIA RTX 4000 Ada Generation"
  "NVIDIA GeForce RTX 4090"
  "NVIDIA L4"
  "NVIDIA A40"
)

_endpoint_list() {
  local body
  body="$(rp::http GET /endpoints)"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  rp::table "$body" id name templateId workersMin workersMax idleTimeout
}

_endpoint_get() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp endpoint get <id>"
  local body
  body="$(rp::http GET "/endpoints/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

_endpoint_delete() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp endpoint delete <id>"
  rp::http DELETE "/endpoints/$id" >/dev/null
  rp::ok "deleted endpoint $id"
}

_resolve_gpus_from_volume() {
  local name="$1" id dc
  id="$(rp::lookup_id volume "$name")"
  [[ -n "$id" ]] || rp::notfound "volume '$name' not found"
  dc="$(rp::http GET "/networkvolumes/$id" | jq -r '.dataCenterId')"
  rp::info "resolving in-stock GPUs for NV '$name' (dc=$dc; stock is account-wide)"
  local q='query { gpuTypes { id lowestPrice { stockStatus } } }'
  local wantjson
  wantjson="$(printf '%s\n' "${RP_DEFAULT_GPUS[@]}" | jq -R . | jq -sc .)"
  rp::graphql "$q" | jq -r --argjson want "$wantjson" '
    .gpuTypes
      | map(select(.lowestPrice.stockStatus != null and .lowestPrice.stockStatus != "None"))
      | map(select(.id as $id | $want | index($id)))
      | map(.id) | .[]'
}

_endpoint_create() {
  local name
  name="$(rp::args_get name)"
  if [[ -n "$name" ]] && ! rp::args_has force; then
    local existing
    existing="$(rp::lookup_id endpoint "$name")"
    if [[ -n "$existing" ]]; then
      rp::ok "endpoint '$name' exists: $existing"
      printf '%s\n' "$existing"
      return 0
    fi
  fi
  local hubid
  hubid="$(rp::args_get hub-id)"
  if [[ -n "$hubid" ]]; then
    [[ -z "$(rp::args_get template)" ]] || rp::usage "--hub-id and --template are mutually exclusive"
    _endpoint_create_hub "$hubid"
    return $?
  fi
  local template
  template="$(rp::args_get template)"
  [[ -n "$template" ]] || rp::usage "usage: rp endpoint create --template <id> [--name <n>] [--force] … (see: rp endpoint --help; idempotent by name)"
  local obj='{}'
  rp::obj_set obj templateId "$(rp::json_str "$template")"
  rp::obj_set obj name "$(rp::json_str "$(rp::args_get name)")"
  rp::obj_set obj computeType "$(rp::json_str "$(rp::args_get compute-type GPU)")"
  local nvid nvname gpusfrom gpu
  nvid="$(rp::args_get network-volume-id)"
  nvname="$(rp::args_get network-volume)"
  gpusfrom="$(rp::args_get gpus-from-volume)"
  gpu="$(rp::args_get gpu)"
  if [[ -n "$nvname" && -z "$nvid" ]]; then
    nvid="$(rp::lookup_id volume "$nvname")"
    [[ -n "$nvid" ]] || rp::notfound "network volume '$nvname' not found"
  fi
  if [[ -n "$nvid" ]]; then
    rp::obj_set obj networkVolumeId "$(rp::json_str "$nvid")"
    local dc
    dc="$(rp::http GET "/networkvolumes/$nvid" | jq -r '.dataCenterId')"
    rp::obj_set obj dataCenterIds "$(rp::json_array "$dc")"
    rp::info "endpoint scoped to NV datacenter: $dc"
    [[ -n "$gpusfrom" ]] && gpu="$(_resolve_gpus_from_volume "$gpusfrom" | paste -sd, -)"
  fi
  if [[ -n "$gpu" ]]; then
    rp::obj_set obj gpuTypeIds "$(rp::csv_to_jsonarray "$gpu")"
  fi
  rp::obj_set obj gpuCount "$(rp::args_get_uint gpu-count)"
  rp::obj_set obj workersMin "$(rp::args_get_uint workers-min)"
  rp::obj_set obj workersMax "$(rp::args_get_uint workers-max)"
  rp::obj_set obj idleTimeout "$(rp::args_get_uint idle)"
  rp::obj_set obj scalerType "$(rp::json_str "$(rp::args_get scaler-type)")"
  rp::obj_set obj scalerValue "$(rp::args_get scaler-value)"
  rp::args_has flashboot && rp::obj_set obj flashboot true
  local mincuda execto nvids envcfg
  mincuda="$(rp::args_get min-cuda-version)"
  [[ -n "$mincuda" ]] && rp::obj_set obj minCudaVersion "$(rp::json_str "$mincuda")"
  execto="$(rp::args_get_uint execution-timeout)"
  [[ -n "$execto" ]] && rp::obj_set obj executionTimeoutMs "$((execto * 1000))"
  nvids="$(rp::args_get network-volume-ids)"
  [[ -n "$nvids" ]] && rp::obj_set obj networkVolumeIds "$(rp::csv_to_jsonarray "$nvids")"
  envcfg="$(rp::args_get env)"
  if [[ -n "$envcfg" ]]; then
    [[ -n "$template" ]] && rp::warn "note: --env is ignored when --template is set (bake env into the template instead)"
    rp::obj_set obj env "$(rp::env_to_json "$envcfg")"
  fi
  local res newid
  res="$(rp::http POST /endpoints "$obj")"
  newid="$(printf '%s' "$res" | jq -r '.id')"
  rp::ok "created endpoint: $newid"
  printf '%s\n' "$newid"
}

# Deploy straight from a Hub listing via GraphQL saveEndpoint (runpodctl parity).
# EndpointInput mapping mirrors runpodctl's EndpointCreateGQLInput: gpuIds are
# comma-joined POOL ids (not type names), env lives on the inline template.
# NOTE: this is a write path that creates a real endpoint — in production it
# always runs live; only the unit tests gate it (they mock rp::graphql).
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

  # GPUs: user type names -> pool ids, else the listing config defaults (already pools)
  local gpusfrom gpu poolcsv
  gpusfrom="$(rp::args_get gpus-from-volume)"
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpusfrom" ]]; then
    gpu="$(_resolve_gpus_from_volume "$gpusfrom" | paste -sd, -)"
  fi
  if [[ -n "$gpu" ]]; then
    poolcsv="$(rp::gpu_type_to_pool_csv "$gpu")"
    [[ -n "$poolcsv" ]] || rp::usage "could not map GPU types to serverless pool ids: $gpu"
  else
    poolcsv="$(printf '%s' "$cfg" | jq -r '.gpuIds // empty')"
    [[ -n "$poolcsv" ]] || rp::usage "listing '$hubid' declares no gpuIds — pass --gpu <type,..>"
  fi

  local gpucount cdisk
  gpucount="$(rp::args_get_uint gpu-count "$(printf '%s' "$cfg" | jq -r '.gpuCount // 1')")"
  cdisk="$(printf '%s' "$cfg" | jq -r '.containerDiskInGb // 20')"

  # env: listing defaults, overridden by --env (repeatable). Required vars with no
  # default must come from --env or the worker will fail to start.
  local envuser envjson
  envuser="$(rp::args_get env)"
  if [[ -n "$envuser" ]]; then
    envjson="$(rp::env_to_json "$envuser" | jq -c 'to_entries | map({key:.key, value:.value})')"
  else
    envjson="$(printf '%s' "$cfg" | jq -c '[(.env // [])[] | select(.input.default != null) | {key:.key, value:(.input.default|tostring)}]')"
  fi

  # optional network volume -> scope to its datacentre (locations)
  local nvid nvname dc
  nvid="$(rp::args_get network-volume-id)"
  nvname="$(rp::args_get network-volume)"
  if [[ -n "$nvname" && -z "$nvid" ]]; then
    nvid="$(rp::lookup_id volume "$nvname")"
    [[ -n "$nvid" ]] || rp::notfound "network volume '$nvname' not found"
  fi
  if [[ -n "$nvid" ]]; then
    dc="$(rp::http GET "/networkvolumes/$nvid" | jq -r '.dataCenterId')"
    rp::info "hub endpoint scoped to NV datacentre: $dc"
  fi

  local input vars res newid
  input="$(jq -c -n \
    --arg name "$name" \
    --arg hubid "$hubid" \
    --arg image "$image" \
    --argjson cdisk "$cdisk" \
    --argjson env "$envjson" \
    --arg gpuIds "$poolcsv" \
    --argjson gpuCount "$gpucount" \
    --argjson workersMin "$(rp::args_get_uint workers-min 0)" \
    --argjson workersMax "$(rp::args_get_uint workers-max 0)" \
    --arg nv "$nvid" \
    --arg loc "$dc" \
    '{
      name:$name, hubReleaseId:$hubid,
      template:{name:$name, imageName:$image, containerDiskInGb:$cdisk, dockerArgs:"", env:$env},
      gpuIds:$gpuIds, gpuCount:$gpuCount, workersMin:$workersMin, workersMax:$workersMax
    } + (if ($nv|length)>0 then {networkVolumeId:$nv, locations:$loc} else {} end)')"
  vars="$(jq -c -n --argjson i "$input" '{input:$i}')"
  res="$(rp::graphql 'mutation($input:EndpointInput!){ saveEndpoint(input:$input){ id name } }' "$vars")"
  newid="$(printf '%s' "$res" | jq -r '.saveEndpoint.id')"
  [[ -n "$newid" && "$newid" != "null" ]] || rp::die "saveEndpoint returned no id: $res"
  rp::ok "created endpoint from hub listing $hubid: $newid"
  printf '%s\n' "$newid"
}

_endpoint_scale() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp endpoint scale <id> --min N --max N [--idle S]"
  local obj='{}'
  rp::obj_set obj workersMin "$(rp::args_get_uint min)"
  rp::obj_set obj workersMax "$(rp::args_get_uint max)"
  rp::obj_set obj idleTimeout "$(rp::args_get_uint idle)"
  local res
  res="$(rp::http PATCH "/endpoints/$id" "$obj")"
  if rp::args_has json; then
    printf '%s\n' "$res"
    return
  fi
  rp::ok "scaled endpoint $id"
}

_endpoint_update() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp endpoint update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>]"
  local obj='{}' gpu
  rp::obj_set obj workersMin "$(rp::args_get_uint workers-min)"
  rp::obj_set obj workersMax "$(rp::args_get_uint workers-max)"
  rp::obj_set obj idleTimeout "$(rp::args_get_uint idle)"
  gpu="$(rp::args_get gpu)"
  [[ -n "$gpu" ]] && rp::obj_set obj gpuTypeIds "$(rp::csv_to_jsonarray "$gpu")"
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update"
  local res
  res="$(rp::http PATCH "/endpoints/$id" "$obj")"
  if rp::args_has json; then
    printf '%s\n' "$res"
    return
  fi
  rp::ok "updated endpoint $id"
}

rp::cmd_endpoint() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) _endpoint_list ;;
  get) _endpoint_get ;;
  create) _endpoint_create ;;
  update) _endpoint_update ;;
  scale) _endpoint_scale ;;
  delete) _endpoint_delete ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp endpoint <verb> [flags]
  create --template <id> [--name <n>] [--network-volume <name> | --network-volume-id <id> | --network-volume-ids <id,id>]
         [--gpus-from-volume <name> | --gpu <id,id>] [--workers-min N] [--workers-max N]
         [--idle S] [--gpu-count N] [--flashboot] [--scaler-type T] [--scaler-value V] [--compute-type T]
         [--env K=V]… [--min-cuda-version <ver>] [--execution-timeout <s>] [--hub-id <listing-id>] [--force]
         (idempotent by --name; --hub-id deploys from a Hub listing via GraphQL saveEndpoint)
  list | get <id> | update <id> [--workers-min N] [--workers-max N] [--idle S] [--gpu <ids>]
  scale <id> --min N --max N [--idle S] | delete <id>
EOF
    ;;
  *) rp::usage "unknown endpoint verb: '$verb'" ;;
  esac
}
