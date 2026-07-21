#!/usr/bin/env bash
# `rp volume` — network volume CRUD, S3 model sync, and in-stock GPU lookup.

_model_repo() {
  case "$1" in
  glm) printf 'zai-org/GLM-OCR' ;;
  flash) printf 'infly/Infinity-Parser2-Flash' ;;
  deepseek) printf 'deepseek-ai/DeepSeek-OCR-2' ;;
  *) return 1 ;;
  esac
}

_volume_list() {
  local body
  body="$(rp::http GET /networkvolumes)"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  rp::table "$body" id name size dataCenterId
}

_volume_get() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp volume get <id>"
  local body
  body="$(rp::http GET "/networkvolumes/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

_volume_create() {
  local name size dc
  name="$(rp::args_get name)"
  size="$(rp::args_get_uint size)"
  dc="$(rp::args_get dc)"
  [[ -n "$name" && -n "$size" && -n "$dc" ]] || rp::usage "usage: rp volume create --name <n> --size <gb> --dc <id>"
  rp::warn_unless_s3_dc "$dc"
  if ! rp::args_has force; then
    local existing
    existing="$(rp::lookup_id volume "$name")"
    if [[ -n "$existing" ]]; then
      rp::ok "volume '$name' exists: $existing"
      printf '%s\n' "$existing"
      return 0
    fi
  fi
  local body res newid
  body="$(rp::json_obj name "$(rp::json_str "$name")" size "$size" dataCenterId "$(rp::json_str "$dc")")"
  res="$(rp::http POST /networkvolumes "$body")"
  newid="$(printf '%s' "$res" | jq -r '.id')"
  rp::ok "created volume '$name': $newid ($dc, ${size}GB)"
  printf '%s\n' "$newid"
}

_volume_update() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp volume update <id> [--name <n>] [--size <gb>]"
  local obj='{}'
  rp::obj_set obj name "$(rp::json_str "$(rp::args_get name)")"
  rp::obj_set obj size "$(rp::args_get_uint size)"
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update (use --name or --size)"
  local res
  res="$(rp::http PATCH "/networkvolumes/$id" "$obj")"
  if rp::args_has json; then
    printf '%s\n' "$res"
    return
  fi
  rp::ok "updated volume $id"
}

_volume_delete() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp volume delete <id>"
  rp::http DELETE "/networkvolumes/$id" >/dev/null
  rp::ok "deleted volume $id"
}

_volume_sync() {
  local name
  name="$(rp::args_pos)"
  [[ -n "$name" ]] || rp::usage "usage: rp volume sync <name> [--source <dir> | --models glm,flash,deepseek] [--prefix models]"
  local id
  id="$(rp::lookup_id volume "$name")"
  [[ -n "$id" ]] || rp::notfound "volume '$name' not found"
  local rec dc
  rec="$(rp::http GET "/networkvolumes/$id")"
  dc="$(printf '%s' "$rec" | jq -r '.dataCenterId')"
  rp::is_s3_dc "$dc" || rp::usage "volume's datacenter '$dc' is not S3-API supported (see: rp stock dc)"
  local prefix source models
  prefix="$(rp::args_get prefix models)"
  source="$(rp::args_get source)"
  models="$(rp::args_get models)"
  if [[ -n "$source" ]]; then
    [[ -d "$source" ]] || rp::notfound "source dir not found: $source"
    rp::info "syncing $source -> $name (s3://$id/$prefix, dc=$dc)"
    rp::s3_sync "$source" "$id" "$dc" "$prefix"
    rp::ok "synced $source -> $name"
    return 0
  fi
  [[ -n "$models" ]] || rp::usage "provide --source <dir> or --models <glm,flash,deepseek>"
  rp::require_cmd huggingface-cli
  local cache
  cache="${RP_MODEL_CACHE:-$RP_ROOT/.cache/models}"
  mkdir -p "$cache"
  local -a ms
  mapfile -t ms < <(rp::split_csv "$models")
  local m repo
  for m in "${ms[@]}"; do
    repo="$(_model_repo "$m")"
    [[ -n "$repo" ]] || rp::usage "unknown model: $m (expected glm|flash|deepseek)"
    rp::info "fetching $m ($repo) -> $cache/$m"
    huggingface-cli download "$repo" --local-dir "$cache/$m"
    rp::info "uploading -> s3://$id/$prefix/$m"
    rp::s3_sync "$cache/$m" "$id" "$dc" "$prefix/$m"
  done
  rp::ok "synced models [${ms[*]}] -> $name"
}

_volume_ls() {
  local name id dc
  name="$(rp::args_pos)"
  [[ -n "$name" ]] || rp::usage "usage: rp volume ls <name> [--path <remote-path>]"
  id="$(rp::lookup_id volume "$name")"
  [[ -n "$id" ]] || rp::notfound "volume '$name' not found"
  dc="$(rp::http GET "/networkvolumes/$id" | jq -r '.dataCenterId')"
  rp::s3_ls "$id" "$dc" "$(rp::args_get path)"
}

_volume_gpus() {
  local name id dc
  name="$(rp::args_pos)"
  [[ -n "$name" ]] || rp::usage "usage: rp volume gpus <name> [--gpu <id,id>]"
  id="$(rp::lookup_id volume "$name")"
  [[ -n "$id" ]] || rp::notfound "volume '$name' not found"
  dc="$(rp::http GET "/networkvolumes/$id" | jq -r '.dataCenterId')"
  rp::info "volume '$name' is in datacenter $dc (GraphQL stock is account-wide, not per-DC)"
  local q='query { gpuTypes { id displayName memoryInGb lowestPrice { minimumBidPrice stockStatus } } }'
  local data filter
  data="$(rp::graphql "$q")"
  filter="$(rp::args_get gpu)"
  if [[ -n "$filter" ]]; then
    local wantjson
    wantjson="$(rp::split_csv "$filter" | jq -R . | jq -sc .)"
    data="$(printf '%s' "$data" | jq --argjson want "$wantjson" '.gpuTypes | map(select(.id as $id | $want | index($id)))')"
  else
    data="$(printf '%s' "$data" | jq '.gpuTypes')"
  fi
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  printf '%s\t%s\t%s\t%s\n' "GPU" "VRAM_GB" "STOCK" "MIN_BID"
  printf '%s' "$data" | jq -r '.[] | [.id, (.memoryInGb // 0), (.lowestPrice.stockStatus // ""), (.lowestPrice.minimumBidPrice // "")] | @tsv'
}

rp::cmd_volume() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) _volume_list ;;
  get) _volume_get ;;
  create) _volume_create ;;
  update) _volume_update ;;
  delete) _volume_delete ;;
  sync) _volume_sync ;;
  ls) _volume_ls ;;
  gpus) _volume_gpus ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp volume <verb> [flags]
  create --name <n> --size <gb> --dc <id>   (idempotent by name; warns if DC is not S3-capable)
  list | get <id> | update <id> [--name <n>] [--size <gb>] | delete <id>
  sync <name> --source <dir> | --models glm,flash,deepseek  [--prefix models]
  ls <name> [--path <remote-path>]
  gpus <name> [--gpu <id,id>]   (account-wide availability for this NV's datacenter)
EOF
    ;;
  *) rp::usage "unknown volume verb: '$verb'" ;;
  esac
}
