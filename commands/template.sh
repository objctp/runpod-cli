#!/usr/bin/env bash
# `rp template` — pod/serverless template CRUD + name-substring search (REST).

_template_list() {
  local body
  body="$(rp::http GET /templates)"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  rp::table "$body" id name imageName isServerless
}

_template_get() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp template get <id>"
  local body
  body="$(rp::http GET "/templates/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

_template_search() {
  local needle
  needle="$(rp::args_pos)"
  [[ -n "$needle" ]] || rp::usage "usage: rp template search <name-substring>"
  local body rows
  body="$(rp::http GET /templates)"
  rows="$(printf '%s' "$body" | jq -c --arg n "$needle" '
    def arr: if type == "array" then .
             elif type == "object" then (.data // .templates // [])
             else [] end;
    arr | map(select((.name // "") | ascii_downcase | contains($n | ascii_downcase)))')"
  if rp::args_has json; then
    printf '%s\n' "$rows"
    return
  fi
  rp::table "$rows" id name imageName isServerless
}

_template_create() {
  local name image
  name="$(rp::args_get name)"
  image="$(rp::args_get image)"
  [[ -n "$name" && -n "$image" ]] || rp::usage "usage: rp template create --name <n> --image <img> [--docker-cmd <a,b>] [--env K=V]… [--serverless] [--ports <a/b>] [--volume-gb N] [--container-disk-gb N] [--force]  (idempotent by name; --env repeatable)"
  if ! rp::args_has force; then
    local existing
    existing="$(rp::lookup_id template "$name")"
    if [[ -n "$existing" ]]; then
      rp::ok "template '$name' exists: $existing"
      printf '%s\n' "$existing"
      return 0
    fi
  fi
  local obj='{}' cmd env ports vol_gb
  rp::obj_set obj name "$(rp::json_str "$name")"
  rp::obj_set obj imageName "$(rp::json_str "$image")"
  rp::args_has serverless && rp::obj_set obj isServerless true
  cmd="$(rp::args_get docker-cmd)"
  env="$(rp::args_get env)"
  ports="$(rp::args_get ports)"
  [[ -n "$cmd" ]] && rp::obj_set obj dockerStartCmd "$(rp::csv_to_jsonarray "$cmd")"
  [[ -n "$env" ]] && rp::obj_set obj env "$(rp::env_to_json "$env")"
  [[ -n "$ports" ]] && rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  vol_gb="$(rp::args_get_uint volume-gb)"
  if rp::args_has serverless && [[ -n "$vol_gb" ]]; then
    rp::warn "ignoring --volume-gb: serverless templates reject volumeInGb"
  else
    rp::obj_set obj volumeInGb "$vol_gb"
  fi
  rp::obj_set obj containerDiskInGb "$(rp::args_get_uint container-disk-gb)"
  local res newid
  res="$(rp::http POST /templates "$obj")"
  newid="$(printf '%s' "$res" | jq -r '.id')"
  rp::ok "created template: $newid"
  printf '%s\n' "$newid"
}

_template_delete() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp template delete <id>"
  rp::http DELETE "/templates/$id" >/dev/null
  rp::ok "deleted template $id"
}

rp::cmd_template() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) _template_list ;;
  get) _template_get ;;
  create) _template_create ;;
  search) _template_search ;;
  delete) _template_delete ;;
  -h | --help | help)
    echo "Usage: rp template <create|list|get|search <name-substring>|delete> (see rp template --help for create flags)"
    ;;
  *) rp::usage "unknown template verb: '$verb'" ;;
  esac
}
