#!/usr/bin/env bash
#
# On-demand GPU and CPU pod lifecycle.
#
# A pod is a single container billed per second, built from an image (or from a
# template's container config) and addressed by id. Every pod is either a GPU
# pod or a CPU pod, never both. Storage is one host-local persistent volume or
# one network volume, and the choice is fixed at create time.
#
# Usage: rp pod <verb> [flags]
#

_pod_simple() {
  local action="$1" id
  rp::require_pos id "usage: rp pod $action <id>"
  rp::http POST "/pods/$id/action" "$(rp::json_obj action "$(rp::json_str "$action")")" >/dev/null
  rp::ok "$action pod $id"
}

_pod_update() {
  local id
  rp::require_pos id "usage: rp pod update <id> [--container-disk-gb N] [--volume-gb N] [--volume-path <p>] [--name <n>] [--image <img>] [--global-networking true|false] [--locked true|false] [--ports <a/b>] [--env K=V]… [--start-cmd <a,b,...>] [--registry <id>] (see: rp pod --help)"
  local obj='{}' disk vol_gb name image ports start env
  disk="$(rp::args_get_uint container-disk-gb)"
  rp::obj_set obj disk "$disk"
  vol_gb="$(rp::args_get_uint volume-gb)"
  if [[ -n "$vol_gb" ]]; then
    local mpath
    mpath="$(rp::args_get volume-path)"
    rp::obj_set obj mounts "$(rp::json_persistent_mount "$vol_gb" "$mpath")"
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
  local registry
  registry="$(rp::args_get registry)"
  if [[ -n "$registry" ]]; then
    rp::obj_set obj registry "$(rp::json_str "$registry")"
  fi
  local gn lk
  rp::require_bool gn global-networking
  rp::obj_set obj globalNetworking "$gn"
  rp::require_bool lk locked
  rp::obj_set obj locked "$lk"
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
  rp::obj_set obj cloud "$(rp::json_str "$(rp::args_get cloud "$RP_DEFAULT_CLOUD")")"

  local disk vol_gb
  disk="$(rp::args_get_uint container-disk-gb)"
  rp::obj_set obj disk "$disk"
  vol_gb="$(rp::args_get_uint volume-gb)"
  if [[ -n "$vol_gb" ]]; then
    local mpath
    mpath="$(rp::args_get volume-path)"
    obj="$(_json_merge "$obj" "$(rp::json_obj mounts "$(rp::json_persistent_mount "$vol_gb" "$mpath")")")"
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
  local registry
  registry="$(rp::args_get registry)"
  if [[ -n "$registry" ]]; then
    rp::obj_set obj registry "$(rp::json_str "$registry")"
  fi

  local gpu first_gpu gcount
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpu" ]]; then
    first_gpu="$(rp::split_csv "$gpu" | head -n1)"
    if [[ "$gpu" == *,* ]]; then
      rp::warn "v2 supports one GPU type per pod; using the first ($first_gpu)"
    fi
    gcount="$(rp::args_get_uint gpu-count "$RP_DEFAULT_GPU_COUNT")"
    obj="$(_json_merge "$obj" "$(rp::json_obj gpu "$(rp::json_gpu_pod "$first_gpu" "$gcount")")")"
  fi

  # CPU-only pod: exactly one of gpu/cpu, vcpuCount a power of two >= 2, and no
  # persistent mount (the spec rejects mounts.persistent when cpu is set —
  # --network-volume-id is the supported storage for CPU pods).
  local cpu_flavor vcpu
  cpu_flavor="$(rp::args_get cpu-flavor)"
  if [[ -n "$cpu_flavor" ]]; then
    [[ -z "$gpu" ]] || rp::usage "--cpu-flavor is mutually exclusive with --gpu (a pod uses exactly one)"
    rp::args_has vcpu || rp::usage "--cpu-flavor requires --vcpu <n> (see: rp pod --help)"
    vcpu="$(rp::args_get_uint vcpu)"
    ((vcpu >= 2)) || rp::usage "--vcpu must be >= 2"
    (((vcpu & (vcpu - 1)) == 0)) || rp::usage "--vcpu must be a power of two (2, 4, 8, …)"
    [[ -z "$vol_gb" ]] || rp::usage "CPU pods take no persistent volume; use --network-volume-id instead"
    obj="$(_json_merge "$obj" "$(rp::json_obj cpu "$(rp::json_cpu "$cpu_flavor" "$vcpu")")")"
  elif rp::args_has vcpu; then
    rp::usage "--vcpu requires --cpu-flavor <id> (see: rp pod --help)"
  fi

  local gn
  rp::require_bool gn global-networking
  if [[ "$gn" == "true" && -n "$cpu_flavor" ]]; then
    rp::usage "--global-networking requires an NVIDIA GPU and is incompatible with --cpu-flavor"
  fi
  rp::obj_set obj globalNetworking "$gn"

  local nv
  nv="$(rp::args_get network-volume-id)"
  if [[ -n "$nv" ]]; then
    [[ -z "$vol_gb" ]] || rp::usage "--volume-gb and --network-volume-id are mutually exclusive (a pod takes one mount kind)"
    local mpath
    mpath="$(rp::args_get volume-path)"
    obj="$(_json_merge "$obj" "$(rp::json_obj mounts "$(rp::json_obj network "$(rp::json_nv_mount "$nv" "$mpath")")")")"
  fi

  local template tmpl
  template="$(rp::args_get template)"
  if [[ -n "$template" ]]; then
    # v2 has no templateId param: spread the template's container-config fields
    # as defaults, letting explicit flags override them.
    tmpl="$(rp::template_spread "$template")"
    obj="$(_json_merge "$tmpl" "$obj")"
  fi

  if rp::args_has interruptible; then
    rp::warn "note: --interruptible has no v2 equivalent and was ignored"
  fi

  rp::resource_create pod "" "$obj"
}

_pod_logs() {
  local id src tail since leid q
  rp::require_pos id "usage: rp pod logs <id> [--source container|system] [--tail N] [--since <rfc3339>] [--last-event-id <ts>]"
  src="$(rp::args_get source)"
  case "$src" in '' | container | system) ;; *) rp::usage "invalid --source '$src' (expected container|system)" ;; esac
  tail="$(rp::args_get_uint tail)"
  [[ -z "$tail" ]] || ((tail <= RP_LOG_TAIL_MAX)) || rp::usage "--tail must be <= $RP_LOG_TAIL_MAX (got $tail)"
  since="$(rp::args_get since)"
  leid="$(rp::args_get last-event-id)"
  q="$(rp::query_params source "$src" tail "$tail" since "$since")"
  rp::stream_rest "/pods/$id/logs$q" "$leid"
}

###
### :::: documentation (rp doc pod) :::: ######################################
###

# doc: create
# Create a pod from an image, optionally seeded by a template.
#
# Usage: rp pod create --image <ref> --name <n>
#                      (--gpu <type> | --cpu-flavor <id> --vcpu N) [flags]
#
# Options:
#   --image <ref>                  Docker image reference (required)
#   --name <n>                     pod name (required)
#   --gpu <type>                   GPU type id — see `rp stock gpu`
#   --gpu-count N                  GPUs to attach (default: 1)
#   --cpu-flavor <id>              CPU flavour id — see `rp stock cpus`
#   --vcpu N                       vCPUs; a power of two, minimum 2
#   --cloud SECURE|COMMUNITY       hardware tier (default: SECURE)
#   --dc <id,…>                    preferred datacentres; omit to let the
#                                  scheduler place the pod
#   --volume-gb N                  host-local persistent volume, GB (minimum 10)
#   --network-volume-id <id>       attach an existing network volume instead
#   --volume-path <path>           mount path for either volume kind
#                                  (default: /workspace)
#   --container-disk-gb N          ephemeral container disk, GB (minimum 1)
#   --global-networking true|false give the pod a private IP reachable across
#                                  datacentres; omit for the API default (false)
#   --ports <a/b,…>                exposed ports, each as port/protocol
#   --env K=V                      environment variable; repeatable
#   --start-cmd <a,b,…>            arguments passed to the container entrypoint
#   --template <id>                template whose container config seeds the pod
#   --registry <id>                registry credential for a private image
#
# Notes:
#   A pod is either a GPU pod or a CPU pod: pass --gpu or --cpu-flavor, never
#   both. The API rejects a create that sets neither, and the CLI does not
#   pre-check that, so the failure arrives as an API error.
#   --name is likewise required by the API but not by the CLI, which only
#   checks --image.
#   --image is required even with --template, and always wins over the
#   template's own image.
#   Storage is one kind or the other: --volume-gb is host-local, pinned to the
#   machine and lost if that host fails, whilst --network-volume-id is durable
#   and must already live in the pod's datacentre. CPU pods reject --volume-gb.
#   The mount kind is fixed at create — `rp pod update` cannot switch it.
#   --gpu takes a single type in v2. A comma-separated list is still accepted,
#   but only the first entry is used and a warning is printed.
#   --global-networking needs an NVIDIA GPU and a datacentre that supports it,
#   so it is rejected alongside --cpu-flavor.
#   v2 has no templateId parameter. --template fetches the template and spreads
#   its container config as defaults, which any explicit flag then overrides.
#   --interruptible is accepted and ignored: v2 has no interruptible pod tier.
#   --force is accepted and ignored. Unlike `rp volume create` and
#   `rp template create`, pod creation is not idempotent by name, so re-running
#   this command creates a second pod.
#
# Examples:
#   rp pod create --name trainer --image runpod/pytorch:2.2.0 \
#     --gpu "NVIDIA GeForce RTX 4090" --container-disk-gb 50
#   rp pod create --name cpu-box --image alpine --cpu-flavor cpu5c --vcpu 4
#   rp pod create --name shared --image alpine --gpu "NVIDIA L4" \
#     --network-volume-id vol_xyz --volume-path /runpod-volume
#
# API: POST /v2/pods

# doc: list
# List your pods as a table: id, name, image, status, cost.
#
# Usage: rp pod list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N        return at most N pods
#   --cursor <c>     offset to resume from; pairs with --limit
#   --jq <filter>    jq filter applied to the array
#   --json           print the raw API response
#
# Notes:
#   status is one of PROVISIONING, STARTING, RUNNING, EXITED, ERROR or
#   TERMINATED.
#   Paging is client-side: the whole list is fetched, then sliced. When output
#   is truncated the next cursor is printed to stderr, leaving stdout clean.
#
# API: GET /v2/pods

# doc: get
# Show one pod's full record, including runtime ports and utilisation.
#
# Usage: rp pod get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>             pod id — from `rp pod list`
#
# Options:
#   --jq <filter>    jq filter applied to the record
#   --json           print the raw API response instead of pretty JSON
#
# Notes:
#   runtime is null until the pod reaches RUNNING, which is why
#   `rp ssh info` reports no connection line for a stopped pod.
#
# API: GET /v2/pods/{id}

# doc: update
# Change a pod's configuration in place, restarting it.
#
# Usage: rp pod update <id> [flags]
#
# Arguments:
#   <id>                           pod id — from `rp pod list`
#
# Options:
#   --name <n>                     rename the pod
#   --image <ref>                  Docker image reference
#   --container-disk-gb N          ephemeral container disk, GB (minimum 1)
#   --volume-gb N                  resize the host-local persistent volume, GB
#   --volume-path <path>           mount path (default: /workspace)
#   --ports <a/b,…>                exposed ports, each as port/protocol
#   --env K=V                      environment variable; repeatable
#   --start-cmd <a,b,…>            arguments passed to the container entrypoint
#   --registry <id>                registry credential for a private image
#   --global-networking true|false enable or disable global networking; omit to
#                                  leave it unchanged
#   --locked true|false            lock the pod against stop and restart; omit
#                                  to leave it unchanged
#   --json                         print the raw API response
#
# Notes:
#   This resets a running pod. Anything outside /workspace or a network volume
#   is wiped, and the CLI prints a reminder before sending the request.
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty PATCH.
#   The mount kind is fixed at create. Introducing a kind the pod was not
#   created with — persistent on a network pod, or either on a pod created
#   without a mount — is rejected by the API.
#   A network volume's id is immutable; only its mount path may change.
#   --global-networking takes effect on the next start or restart, not live.
#   A locked pod cannot be stopped or restarted until it is unlocked.
#
# Examples:
#   rp pod update pod_abc123 --name renamed
#   rp pod update pod_abc123 --container-disk-gb 80 --env HF_TOKEN=xxx
#
# API: PATCH /v2/pods/{id}

# doc: delete
# Terminate a pod permanently.
#
# Usage: rp pod delete <id>
#
# Arguments:
#   <id>             pod id — from `rp pod list`
#
# Notes:
#   Termination is irreversible and is not the same as `rp pod stop`: a stopped
#   pod keeps its disks and can be started again, whilst a terminated one is
#   gone.
#   Host-local persistent storage dies with the pod. An attached network volume
#   outlives it and must be removed with `rp volume delete`.
#
# API: DELETE /v2/pods/{id}

# doc: start
# Start a stopped pod.
#
# Usage: rp pod start <id>
#
# Arguments:
#   <id>             pod id — from `rp pod list`
#
# Notes:
#   Starting is asynchronous: the command returns once the transition is
#   accepted, not once the container is RUNNING. Poll with `rp pod get <id>`.
#   A start can fail later if the pod's GPU type is out of stock in its
#   datacentre.
#
# API: POST /v2/pods/{id}/action  (action: start)

# doc: stop
# Stop a running pod, keeping its disks.
#
# Usage: rp pod stop <id>
#
# Arguments:
#   <id>             pod id — from `rp pod list`
#
# Notes:
#   A stopped pod still bills for its storage, only the GPU or CPU charge
#   ceases. Use `rp pod delete` to stop paying entirely.
#   A locked pod refuses to stop; unlock it with
#   `rp pod update <id> --locked false`.
#
# API: POST /v2/pods/{id}/action  (action: stop)

# doc: reset
# Deprecated: alias for `restart` — v2 removed the reset action.
#
# Usage: rp pod reset <id>
#
# Notes:
#   v2's action enum is start, stop, restart and terminate; there is no reset.
#   The verb is kept so existing scripts keep working: it warns and performs a
#   restart. Use `rp pod restart` instead.
#
# API: POST /v2/pods/{id}/action  (action: restart)

# doc: restart
# Restart a running pod.
#
# Usage: rp pod restart <id>
#
# Arguments:
#   <id>             pod id — from `rp pod list`
#
# Notes:
#   The container is recreated, so anything written outside /workspace or a
#   network volume is lost.
#   A locked pod refuses to restart.
#
# API: POST /v2/pods/{id}/action  (action: restart)

# doc: logs
# Stream a pod's container and system logs live.
#
# Usage: rp pod logs <id> [--source container|system] [--tail N]
#                    [--since <rfc3339>] [--last-event-id <ts>]
#
# Arguments:
#   <id>                      pod id — from `rp pod list`
#
# Options:
#   --source container|system restrict the stream; omit for both
#   --tail N                  historical lines to backfill (default: 100,
#                             maximum 5000); 0 streams live with no backfill
#   --since <rfc3339>         resume from a timestamp instead of backfilling
#   --last-event-id <ts>      SSE reconnect cursor emitted by this endpoint
#
# Notes:
#   The stream is Server-Sent Events written raw to stdout, so it pipes and
#   redirects cleanly and there is no --json. Ctrl-C ends it.
#   The three resume flags have a precedence: --last-event-id beats --since,
#   which beats --tail. Setting a lower-precedence flag alongside a higher one
#   has no effect.
#   container is the container's stdout and stderr; system is the host
#   lifecycle log, which is where pull failures and OOM kills appear.
#
# Examples:
#   rp pod logs pod_abc123 --tail 0
#   rp pod logs pod_abc123 --source system --tail 500
#
# API: GET /v2/pods/{id}/logs

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
  logs) _pod_logs ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp pod <verb> [flags]
  create --image <img> [--name <n>] [--gpu <id>] [--gpu-count N] [--dc <id,id>]
          [--cpu-flavor <id>] [--vcpu <n>]   (CPU-only pod; excludes --gpu and --volume-gb)
          [--cloud SECURE|COMMUNITY] [--network-volume-id <id>] [--volume-gb N] [--container-disk-gb N]
          [--volume-path <p>] [--global-networking true|false] [--ports <a/b,...>] [--env K=V]…
          [--start-cmd <a,b,...>] [--template <id>] [--registry <id>]
  update <id> [--container-disk-gb N] [--volume-gb N] [--volume-path <p>] [--name <n>] [--image <img>]
          [--global-networking true|false] [--locked true|false]
          [--ports <a/b,...>] [--env K=V]… [--start-cmd <a,b,...>] [--registry <id>]   (PATCH; resets a running pod)
  list | get <id> | start|stop|restart <id> | logs <id> | delete <id>   (reset is an alias for restart; v2 dropped it)
  logs <id> [--source container|system] [--tail N] [--since <rfc3339>] [--last-event-id <ts>]   (live SSE stream; --tail 0 = live only)
EOF
    ;;
  *) rp::usage "unknown pod verb: '$verb'" ;;
  esac
}
