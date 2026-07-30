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

_volume_create() {
  local name size dc
  name="$(rp::args_get name)"
  size="$(rp::args_get size)"
  rp::require_uint "$size" size
  dc="$(rp::args_get dc)"
  [[ -n "$name" && -n "$size" && -n "$dc" ]] || rp::usage "usage: rp volume create --name <n> --size <gb> --dc <id>"
  rp::warn_unless_s3_dc "$dc"
  local body
  body="$(rp::json_obj name "$(rp::json_str "$name")" size "$size" dataCenter "$(rp::json_str "$dc")")"
  rp::resource_create volume "$name" "$body" "$dc, ${size}GB"
}

_volume_update() {
  local id
  rp::require_pos id "usage: rp volume update <id> [--name <n>] [--size <gb>]"
  local obj='{}'
  local name size
  name="$(rp::args_get name)"
  if [[ -n "$name" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name")"
  fi
  size="$(rp::args_get size)"
  rp::require_uint "$size" size
  if [[ -n "$size" ]]; then
    rp::obj_set obj size "$size"
  fi
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update (use --name or --size)"
  local res
  res="$(rp::http PATCH "/network-volumes/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated volume $id"
}

_volume_sync() {
  local name
  rp::require_pos name "usage: rp volume sync <name> [--source <dir> | --models glm,flash,deepseek] [--prefix models]"
  rp::volume_dc "$name"
  local id="$RP_VOLUME_ID" dc="$RP_VOLUME_DC"
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
    repo="$(_model_repo "$m")" || rp::usage "unknown model: $m (expected glm|flash|deepseek)"
    [[ -n "$repo" ]] || rp::usage "unknown model: $m (expected glm|flash|deepseek)"
    rp::info "fetching $m ($repo) -> $cache/$m"
    huggingface-cli download "$repo" --local-dir "$cache/$m"
    rp::info "uploading -> s3://$id/$prefix/$m"
    rp::s3_sync "$cache/$m" "$id" "$dc" "$prefix/$m"
  done
  rp::ok "synced models [${ms[*]}] -> $name"
}

_volume_ls() {
  local name
  rp::require_pos name "usage: rp volume ls <name> [--path <remote-path>]"
  rp::volume_dc "$name"
  rp::s3_ls "$RP_VOLUME_ID" "$RP_VOLUME_DC" "$(rp::args_get path)"
}

_volume_gpus() {
  local name
  rp::require_pos name "usage: rp volume gpus <name> [--gpu <id,id>]"
  rp::volume_dc "$name"
  rp::info "volume '$name' is in datacenter $RP_VOLUME_DC (catalog stock is account-wide, not per-DC)"
  local data
  data="$(rp::http GET '/catalog/gpus?include=AVAILABILITY&product=POD,SERVERLESS' | rp::unwrap gpus)"
  local filter
  filter="$(rp::args_get gpu)"
  if [[ -n "$filter" ]]; then
    local wantjson
    wantjson="$(rp::split_csv "$filter" | jq -R . | jq -sc .)"
    data="$(printf '%s' "$data" | jq --argjson want "$wantjson" 'map(select(.id as $id | $want | index($id)))')"
  fi
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({GPU:.id, VRAM_GB:(.memory//0), STOCK:(.availability//""), SECURE_PRICE:(.price.secure//"")})' \
    GPU VRAM_GB STOCK SECURE_PRICE
}

rp::cmd_volume() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list volume id name size dataCenter ;;
  get) rp::resource_get volume ;;
  create) _volume_create ;;
  update) _volume_update ;;
  delete) rp::resource_delete volume ;;
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
