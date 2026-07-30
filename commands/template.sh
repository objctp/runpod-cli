#!/usr/bin/env bash
#
# `rp template` — pod/serverless template CRUD + name-substring search (REST API v2).
# Usage: rp template <verb> [flags]
#

_template_search() {
  local needle
  rp::require_pos needle "usage: rp template search <name-substring>"
  local arr rows
  arr="$(rp::http GET /templates | rp::unwrap templates)"
  rows="$(printf '%s' "$arr" | jq -c --arg n "$needle" 'map(select((.name // "") | ascii_downcase | contains($n | ascii_downcase)))')"
  rp::emit_json_or "$rows" rp::table "$rows" id name image serverless
}

_template_create() {
  local name image
  name="$(rp::args_get name)"
  image="$(rp::args_get image)"
  [[ -n "$name" && -n "$image" ]] || rp::usage "usage: rp template create --name <n> --image <img> [--docker-cmd <a,b>] [--env K=V]… [--serverless] [--ports <a/b>] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--force]  (idempotent by name; --env repeatable)"
  local obj='{}'
  rp::obj_set obj name "$(rp::json_str "$name")"
  rp::obj_set obj image "$(rp::json_str "$image")"
  rp::args_has serverless && rp::obj_set obj serverless true
  local cmd env ports vol_gb cdisk
  cmd="$(rp::args_get docker-cmd)"
  [[ -n "$cmd" ]] && rp::obj_set obj args "$(rp::json_str "$(rp::csv_to_argstring "$cmd")")"
  env="$(rp::args_get env)"
  [[ -n "$env" ]] && rp::obj_set obj env "$(rp::env_to_json "$env")"
  ports="$(rp::args_get ports)"
  [[ -n "$ports" ]] && rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  vol_gb="$(rp::args_get_uint volume-gb)"
  if rp::args_has serverless && [[ -n "$vol_gb" ]]; then
    rp::warn "ignoring --volume-gb: serverless templates reject volumeInGb"
  elif [[ -n "$vol_gb" ]]; then
    rp::obj_set obj mounts "$(rp::json_persistent_mount "$vol_gb")"
  fi
  cdisk="$(rp::args_get_uint container-disk-gb)"
  [[ -n "$cdisk" ]] && rp::obj_set obj disk "$cdisk"
  rp::obj_set obj category "$(rp::json_str "$(rp::args_get category NVIDIA)")"
  rp::resource_create template "$name" "$obj"
}

rp::cmd_template() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list template id name image serverless ;;
  get) rp::resource_get template ;;
  create) _template_create ;;
  search) _template_search ;;
  delete) rp::resource_delete template ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp template <verb> [flags]
  create --name <n> --image <img> [--serverless] [--docker-cmd <a,b>] [--env K=V]… [--ports <a/b>] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--force]
         (idempotent by --name; --env repeatable; --category defaults to NVIDIA)
  list | get <id> | search <name-substring> | delete <id>
EOF
    ;;
  *) rp::usage "unknown template verb: '$verb'" ;;
  esac
}
