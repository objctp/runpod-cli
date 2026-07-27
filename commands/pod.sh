#!/usr/bin/env bash
# `rp pod` — on-demand pod CRUD (REST).

_pod_list() {
  local body
  body="$(rp::http GET /pods)"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  rp::table "$body" id name image desiredStatus costPerHr
}

_pod_get() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp pod get <id>"
  local body
  body="$(rp::http GET "/pods/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

_pod_simple() {
  local action="$1" id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp pod $action <id>"
  rp::http POST "/pods/$id/$action" >/dev/null
  rp::ok "$action pod $id"
}

_pod_delete() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp pod delete <id>"
  rp::http DELETE "/pods/$id" >/dev/null
  rp::ok "deleted pod $id"
}

_pod_update() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp pod update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>] [--ports <a/b>] [--env K=V] [--start-cmd <a,b>] (see: rp pod --help)"
  local obj='{}' name image ports start env
  rp::obj_set obj containerDiskInGb "$(rp::args_get_uint container-disk-gb)"
  rp::obj_set obj volumeInGb "$(rp::args_get_uint volume-gb)"
  name="$(rp::args_get name)"
  [[ -n "$name" ]] && rp::obj_set obj name "$(rp::json_str "$name")"
  image="$(rp::args_get image)"
  [[ -n "$image" ]] && rp::obj_set obj imageName "$(rp::json_str "$image")"
  ports="$(rp::args_get ports)"
  [[ -n "$ports" ]] && rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  start="$(rp::args_get start-cmd)"
  [[ -n "$start" ]] && rp::obj_set obj dockerStartCmd "$(rp::csv_to_jsonarray "$start")"
  env="$(rp::args_get env)"
  [[ -n "$env" ]] && rp::obj_set obj env "$(rp::env_to_json "$env")"
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update (see: rp pod update --help)"
  rp::info "note: updating a running pod resets it — data outside /workspace or a network volume is wiped"
  local res
  res="$(rp::http PATCH "/pods/$id" "$obj")"
  if rp::args_has json; then
    printf '%s\n' "$res"
    return
  fi
  rp::ok "updated pod $id"
}

_pod_create() {
  local image
  image="$(rp::args_get image)"
  [[ -n "$image" ]] || rp::usage "usage: rp pod create --image <img> (see: rp pod --help)"
  local obj='{}' gpu dc ports start env
  rp::obj_set obj imageName "$(rp::json_str "$image")"
  rp::obj_set obj name "$(rp::json_str "$(rp::args_get name)")"
  rp::obj_set obj cloudType "$(rp::json_str "$(rp::args_get cloud SECURE)")"
  gpu="$(rp::args_get gpu)"
  dc="$(rp::args_get dc)"
  ports="$(rp::args_get ports)"
  start="$(rp::args_get start-cmd)"
  env="$(rp::args_get env)"
  [[ -n "$gpu" ]] && rp::obj_set obj gpuTypeIds "$(rp::csv_to_jsonarray "$gpu")"
  [[ -n "$dc" ]] && rp::obj_set obj dataCenterIds "$(rp::csv_to_jsonarray "$dc")"
  [[ -n "$ports" ]] && rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  [[ -n "$start" ]] && rp::obj_set obj dockerStartCmd "$(rp::csv_to_jsonarray "$start")"
  [[ -n "$env" ]] && rp::obj_set obj env "$(rp::env_to_json "$env")"
  rp::obj_set obj gpuCount "$(rp::args_get_uint gpu-count)"
  rp::obj_set obj networkVolumeId "$(rp::json_str "$(rp::args_get network-volume-id)")"
  rp::obj_set obj volumeInGb "$(rp::args_get_uint volume-gb)"
  rp::obj_set obj containerDiskInGb "$(rp::args_get_uint container-disk-gb)"
  rp::obj_set obj templateId "$(rp::json_str "$(rp::args_get template)")"
  rp::args_has interruptible && rp::obj_set obj interruptible true
  local res newid
  res="$(rp::http POST /pods "$obj")"
  newid="$(printf '%s' "$res" | jq -r '.id')"
  rp::ok "created pod: $newid"
  printf '%s\n' "$newid"
}

rp::cmd_pod() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _pod_create ;;
  list) _pod_list ;;
  get) _pod_get ;;
  update) _pod_update ;;
  delete) _pod_delete ;;
  start) _pod_simple start ;;
  stop) _pod_simple stop ;;
  reset) _pod_simple reset ;;
  restart) _pod_simple restart ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp pod <verb> [flags]
  create --image <img> [--name <n>] [--gpu <id,id>] [--gpu-count N] [--dc <id,id>]
         [--cloud SECURE|COMMUNITY] [--network-volume-id <id>] [--volume-gb N] [--container-disk-gb N]
         [--ports <a/b,...>] [--env K=V]… [--start-cmd <a,b,...>] [--template <id>] [--interruptible]
  update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>]
         [--ports <a/b,...>] [--env K=V]… [--start-cmd <a,b,...>]   (PATCH; resets a running pod)
  list | get <id> | start|stop|reset|restart <id> | delete <id>
EOF
    ;;
  *) rp::usage "unknown pod verb: '$verb'" ;;
  esac
}
