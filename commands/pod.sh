#!/usr/bin/env bash
# `rp pod` — on-demand pod CRUD (REST API v2).

_pod_simple() {
  local action="$1" id
  rp::require_pos id "usage: rp pod $action <id>"
  rp::http POST "/pods/$id/action" "$(rp::json_obj action "$(rp::json_str "$action")")" >/dev/null
  rp::ok "$action pod $id"
}

_pod_update() {
  local id
  rp::require_pos id "usage: rp pod update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>] [--ports <a/b>] [--env K=V]… [--start-cmd <a,b,...>] (see: rp pod --help)"
  local obj='{}' disk vol_gb name image ports start env
  disk="$(rp::args_get container-disk-gb)"
  rp::require_uint "$disk" container-disk-gb
  rp::obj_set obj disk "$disk"
  vol_gb="$(rp::args_get volume-gb)"
  rp::require_uint "$vol_gb" volume-gb
  if [[ -n "$vol_gb" ]]; then
    rp::obj_set obj mounts "$(rp::json_persistent_mount "$vol_gb")"
  fi
  name="$(rp::args_get name)"
  if [[ -n "$name" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name")"
  fi
  image="$(rp::args_get image)"
  if [[ -n "$image" ]]; then
    rp::obj_set obj image "$(rp::json_str "$image")"
  fi
  ports="$(rp::args_get ports)"
  if [[ -n "$ports" ]]; then
    rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  fi
  start="$(rp::args_get start-cmd)"
  if [[ -n "$start" ]]; then
    rp::obj_set obj args "$(rp::json_str "$(rp::csv_to_argstring "$start")")"
  fi
  env="$(rp::args_get env)"
  if [[ -n "$env" ]]; then
    rp::obj_set obj env "$(rp::env_to_json "$env")"
  fi
  [[ "$obj" != '{}' ]] || rp::usage "nothing to update (see: rp pod update --help)"
  rp::info "note: updating a running pod resets it — data outside /workspace or a network volume is wiped"
  local res
  res="$(rp::http PATCH "/pods/$id" "$obj")"
  rp::emit_json_or "$res" rp::ok "updated pod $id"
}

_pod_create() {
  local image
  image="$(rp::args_get image)"
  [[ -n "$image" ]] || rp::usage "usage: rp pod create --image <img> (see: rp pod --help)"

  local obj='{}'
  local name_val
  name_val="$(rp::args_get name)"
  if [[ -n "$name_val" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name_val")"
  fi
  rp::obj_set obj image "$(rp::json_str "$image")"
  rp::obj_set obj cloud "$(rp::json_str "$(rp::args_get cloud SECURE)")"

  local disk vol_gb
  disk="$(rp::args_get container-disk-gb)"
  rp::require_uint "$disk" container-disk-gb
  rp::obj_set obj disk "$disk"
  vol_gb="$(rp::args_get volume-gb)"
  rp::require_uint "$vol_gb" volume-gb
  if [[ -n "$vol_gb" ]]; then
    obj="$(_json_merge "$obj" "$(rp::json_obj mounts "$(rp::json_persistent_mount "$vol_gb")")")"
  fi

  local dc ports start env
  dc="$(rp::args_get dc)"
  if [[ -n "$dc" ]]; then
    rp::obj_set obj dataCenterIds "$(rp::csv_to_jsonarray "$dc")"
  fi
  ports="$(rp::args_get ports)"
  if [[ -n "$ports" ]]; then
    rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"
  fi
  start="$(rp::args_get start-cmd)"
  if [[ -n "$start" ]]; then
    rp::obj_set obj args "$(rp::json_str "$(rp::csv_to_argstring "$start")")"
  fi
  env="$(rp::args_get env)"
  if [[ -n "$env" ]]; then
    rp::obj_set obj env "$(rp::env_to_json "$env")"
  fi

  local gpu first_gpu gcount
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpu" ]]; then
    first_gpu="$(rp::split_csv "$gpu" | head -n1)"
    if [[ "$gpu" == *,* ]]; then
      rp::warn "v2 supports one GPU type per pod; using the first ($first_gpu)"
    fi
    gcount="$(rp::args_get gpu-count 1)"
    rp::require_uint "$gcount" gpu-count
    obj="$(_json_merge "$obj" "$(rp::json_obj gpu "$(rp::json_gpu_pod "$first_gpu" "$gcount")")")"
  fi

  local nv
  nv="$(rp::args_get network-volume-id)"
  if [[ -n "$nv" ]]; then
    obj="$(_json_merge "$obj" "$(rp::json_obj mounts "$(rp::json_obj network "$(rp::json_nv_mount "$nv")")")")"
  fi

  local template tmpl
  template="$(rp::args_get template)"
  if [[ -n "$template" ]]; then
    # v2 has no templateId param: spread the template's container-config fields
    # as defaults, letting explicit flags override them.
    tmpl="$(rp::http GET "/templates/$template" | jq -c '{image, args, disk, ports, env, registry} | with_entries(select(.value != null))')"
    obj="$(_json_merge "$tmpl" "$obj")"
  fi

  if rp::args_has interruptible; then
    rp::warn "note: --interruptible has no v2 equivalent and was ignored"
  fi

  rp::resource_create pod "" "$obj"
}

rp::cmd_pod() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _pod_create ;;
  list) rp::resource_list pod id name image status cost ;;
  get) rp::resource_get pod ;;
  update) _pod_update ;;
  delete) rp::resource_delete pod ;;
  start) _pod_simple start ;;
  stop) _pod_simple stop ;;
  reset)
    # v2 PodAction has no `reset` (enum: start|stop|restart|terminate).
    rp::warn "note: v2 dropped the reset action; performing restart instead"
    _pod_simple restart
    ;;
  restart) _pod_simple restart ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp pod <verb> [flags]
  create --image <img> [--name <n>] [--gpu <id>] [--gpu-count N] [--dc <id,id>]
          [--cloud SECURE|COMMUNITY] [--network-volume-id <id>] [--volume-gb N] [--container-disk-gb N]
          [--ports <a/b,...>] [--env K=V]… [--start-cmd <a,b,...>] [--template <id>]
  update <id> [--container-disk-gb N] [--volume-gb N] [--name <n>] [--image <img>]
          [--ports <a/b,...>] [--env K=V]… [--start-cmd <a,b,...>]   (PATCH; resets a running pod)
  list | get <id> | start|stop|restart <id> | delete <id>   (reset is an alias for restart; v2 dropped it)
EOF
    ;;
  *) rp::usage "unknown pod verb: '$verb'" ;;
  esac
}
