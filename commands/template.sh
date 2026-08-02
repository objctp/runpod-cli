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

# Validate --category against the TemplateCategory enum (CPU|NVIDIA|AMD). An empty
# value passes through (create defaults NVIDIA; update omits). Call it as a direct
# call in the main shell so rp::usage's exit propagates — not inside command
# substitution, which would swallow it.
_template_validate_category() {
  case "$1" in
  '' | CPU | NVIDIA | AMD) return 0 ;;
  *) rp::usage "invalid --category '$1' (expected CPU|NVIDIA|AMD)" ;;
  esac
}

_template_create() {
  local name image
  name="$(rp::args_get name)"
  image="$(rp::args_get image)"
  [[ -n "$name" && -n "$image" ]] || rp::usage "usage: rp template create --name <n> --image <img> [--docker-cmd <a,b>] [--env K=V]… [--serverless] [--ports <a/b>] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--public true|false] [--registry <id>] [--force]  (idempotent by name; --env repeatable)"
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
  local registry
  registry="$(rp::args_get registry)"
  if [[ -n "$registry" ]]; then
    rp::obj_set obj registry "$(rp::json_str "$registry")"
  fi
  local category
  category="$(rp::args_get category "$RP_DEFAULT_TEMPLATE_CATEGORY")"
  _template_validate_category "$category"
  rp::obj_set obj category "$(rp::json_str "$category")"
  # Omitted --public leaves the key unset, so the API applies its `false` default.
  local pub
  rp::require_bool pub public
  rp::obj_set obj public "$pub"
  rp::resource_create template "$name" "$obj"
}

_template_update() {
  local id
  rp::require_pos id "usage: rp template update <id> [--name <n>] [--image <img>] [--public true|false] [--registry <id>] [--docker-cmd <a,b>] [--env K=V]… [--ports <a/b>] [--container-disk-gb N] [--volume-gb N] [--category <c>] [--serverless]  (PATCH)"
  local obj='{}' name image cmd env ports cdisk registry category vol_gb pub
  name="$(rp::args_get name)"
  [[ -n "$name" ]] && rp::obj_set obj name "$(rp::json_str "$name")"
  image="$(rp::args_get image)"
  [[ -n "$image" ]] && rp::obj_set obj image "$(rp::json_str "$image")"
  cmd="$(rp::args_get docker-cmd)"
  [[ -n "$cmd" ]] && rp::obj_set obj args "$(rp::json_str "$(rp::csv_to_argstring "$cmd")")"
  env="$(rp::args_get env)"
  [[ -n "$env" ]] && rp::obj_set obj env "$(rp::env_to_json "$env")"
  ports="$(rp::args_get ports)"
  [[ -n "$ports" ]] && rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  cdisk="$(rp::args_get_uint container-disk-gb)"
  [[ -n "$cdisk" ]] && rp::obj_set obj disk "$cdisk"
  registry="$(rp::args_get registry)"
  [[ -n "$registry" ]] && rp::obj_set obj registry "$(rp::json_str "$registry")"
  # Unlike create, category is sent only when given: the spec's defaults are create-side.
  category="$(rp::args_get category)"
  _template_validate_category "$category"
  [[ -n "$category" ]] && rp::obj_set obj category "$(rp::json_str "$category")"
  rp::args_has serverless && rp::obj_set obj serverless true
  rp::require_bool pub public
  rp::obj_set obj public "$pub"
  vol_gb="$(rp::args_get_uint volume-gb)"
  if rp::args_has serverless && [[ -n "$vol_gb" ]]; then
    rp::warn "ignoring --volume-gb: serverless templates reject volumeInGb"
  elif [[ -n "$vol_gb" ]]; then
    rp::obj_set obj mounts "$(rp::json_persistent_mount "$vol_gb")"
  fi
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update (see: rp template update --help)"
  local res
  res="$(rp::http PATCH "/templates/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated template $id"
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
  update) _template_update ;;
  search) _template_search ;;
  delete) rp::resource_delete template ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp template <verb> [flags]
  create --name <n> --image <img> [--serverless] [--docker-cmd <a,b>] [--env K=V]… [--ports <a/b>] [--volume-gb N] [--container-disk-gb N] [--category <c>] [--public true|false] [--registry <id>] [--force]
         (idempotent by --name; --env repeatable; --category defaults to NVIDIA; templates are private unless --public true)
  update <id> [--name <n>] [--image <img>] [--public true|false] [--registry <id>] [--docker-cmd <a,b>] [--env K=V]… [--ports <a/b>] [--container-disk-gb N] [--volume-gb N] [--category <c>] [--serverless]
         (PATCH; every field optional, at least one required)
  list | get <id> | search <name-substring> | delete <id>
EOF
    ;;
  *) rp::usage "unknown template verb: '$verb'" ;;
  esac
}
