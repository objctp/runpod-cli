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
  local image name_val template_id
  image="$(rp::args_get image)"
  template_id="$(rp::args_get template-id)"
  # image is required unless a template supplies the container config (v2 only
  # makes image optional when templateId is set).
  [[ -n "$image" || -n "$template_id" ]] || rp::usage "usage: rp pod create --image <img> (or --template-id <id>) (see: rp pod --help)"
  name_val="$(rp::args_get name)"
  [[ -n "$name_val" ]] || rp::usage "usage: rp pod create --name <n> (see: rp pod --help)"

  # --cost-center must exist before anything is provisioned: the v2 path is
  # gated inside rp::resource_create, but the spot bridge below returns early,
  # so the gate runs here to cover both.
  local pod_cc
  pod_cc="$(rp::args_get cost-center)"
  [[ -z "$pod_cc" ]] || rp::cc_require_center "$pod_cc"

  # --compute-type is a runpodctl coercion alias (not a data field), handled
  # here after the alias layer: it never mints new fields, only requires the
  # matching rp flags be present so the existing gpu/cpu path is selected.
  local compute_type
  compute_type="$(rp::args_get compute-type)"
  compute_type="${compute_type^^}"
  if [[ -n "$compute_type" ]]; then
    case "$compute_type" in
    GPU)
      rp::args_has gpu || rp::usage "usage: rp pod create --compute-type GPU requires --gpu <type> (see: rp pod --help)"
      ;;
    CPU)
      rp::args_has cpu-flavor || rp::usage "usage: rp pod create --compute-type CPU requires --cpu-flavor <id> (see: rp pod --help)"
      rp::args_has vcpu || rp::usage "usage: rp pod create --compute-type CPU requires --vcpu <n> (see: rp pod --help)"
      ;;
    *)
      rp::usage "invalid --compute-type '$compute_type' (expected GPU|CPU)"
      ;;
    esac
  fi

  local obj='{}'
  if [[ -n "$name_val" ]]; then
    rp::obj_set obj name "$(rp::json_str "$name_val")"
  fi
  [[ -z "$image" ]] || rp::obj_set obj image "$(rp::json_str "$image")"
  [[ -z "$template_id" ]] || rp::obj_set obj templateId "$(rp::json_str "$template_id")"
  rp::obj_set obj cloud "$(rp::json_str "$(rp::args_get cloud "$RP_DEFAULT_CLOUD" | tr '[:lower:]' '[:upper:]')")"

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

  local gpu first_gpu gcount gpu_obj min_cuda
  min_cuda="$(rp::args_get min-cuda-version)"
  if [[ -n "$min_cuda" ]]; then
    [[ "$min_cuda" =~ ^[0-9]+\.[0-9]+$ ]] || rp::usage "usage: rp pod create --min-cuda-version must be a version like 12.1 (got '$min_cuda')"
  fi
  gpu="$(rp::args_get gpu)"
  if [[ -n "$gpu" ]]; then
    first_gpu="$(rp::split_csv "$gpu" | head -n1)"
    if [[ "$gpu" == *,* ]]; then
      rp::warn "v2 supports one GPU type per pod; using the first ($first_gpu)"
    fi
    gcount="$(rp::args_get_uint gpu-count "$RP_DEFAULT_GPU_COUNT")"
    gpu_obj="$(rp::json_gpu_pod "$first_gpu" "$gcount")"
    if [[ -n "$min_cuda" ]]; then
      gpu_obj="$(_json_merge "$gpu_obj" "$(rp::json_obj minCudaVersion "$(rp::json_str "$min_cuda")")")"
    fi
    obj="$(_json_merge "$obj" "$(rp::json_obj gpu "$gpu_obj")")"
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

  [[ -n "$gpu" || -n "$cpu_flavor" ]] || rp::usage "usage: rp pod create needs --gpu <type> or --cpu-flavor <id> (exactly one; see: rp pod --help)"

  local gn
  rp::require_bool gn global-networking
  if [[ "$gn" == "true" && -n "$cpu_flavor" ]]; then
    rp::usage "--global-networking requires an NVIDIA GPU and is incompatible with --cpu-flavor"
  fi
  rp::obj_set obj globalNetworking "$gn"

  if rp::args_has public-ip; then
    # Community-cloud pods are not publicly routable by default; supportPublicIp
    # asks the scheduler for a public IP (the runpodctl --public-ip mapping).
    rp::obj_set obj supportPublicIp true
  fi

  if rp::args_has ssh; then
    rp::obj_set obj startSsh "true"
  fi

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

  # Spot / interruptible pods. REST v2 carries these at the body's top level:
  # `interruptible` (boolean) and `bidPerGpu` (number, the max $/GPU-hr you will
  # pay). --bid-per-gpu is the canonical trigger and implies --interruptible;
  # pass --interruptible alone to mark the pod spot and let the server bid the
  # on-demand price. The bid must be a positive number. (The published v2
  # OpenAPI is beta and omits these fields; the request shape matches Runpod's
  # REST spot fields and is what the v2 handler accepts.)
  local bid_per_gpu
  bid_per_gpu="$(rp::args_get bid-per-gpu)"
  if [[ -n "$bid_per_gpu" ]]; then
    [[ "$bid_per_gpu" =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
      rp::usage "usage: rp pod create --bid-per-gpu must be a positive number (got '$bid_per_gpu')"
    [[ "$bid_per_gpu" =~ ^0+(\.0+)?$ ]] &&
      rp::usage "usage: rp pod create --bid-per-gpu must be greater than 0"
    rp::obj_set obj interruptible true
    rp::obj_set obj bidPerGpu "$bid_per_gpu"
  elif rp::args_has interruptible; then
    rp::obj_set obj interruptible true
  fi

  if [[ -n "$bid_per_gpu" ]] || rp::args_has interruptible; then
    # v2 is the future-proof path: send it first with the spot fields. If the
    # server does not yet advertise them it rejects the request; detect that
    # exact rejection and fall back to the deprecated GraphQL bridge below. Once
    # v2 natively supports spot, the v2 branch succeeds and the bridge is dead
    # code to be removed. Honour the same idempotency-by-name gate as
    # rp::resource_create so re-running with an existing name is a no-op.
    if rp::resource_existing pod "$name_val"; then
      rp::cc_tag_quietly "$pod_cc" pod "${RP_RES_EXISTING_ID:-}"
      return 0
    fi
    local _bodyfile _status _newid
    _mktemp _bodyfile
    rp::http_soft "$_bodyfile" POST "/pods" "$obj"
    _status="$_RP_CURL_STATUS"
    if ((_status < 400)); then
      rp::extract_id _newid "$(<"$_bodyfile")" "pod"
      rp::cc_tag_quietly "$pod_cc" pod "$_newid"
      rp::ok "created pod${name_val:+ '$name_val'}: $_newid"
      printf '%s\n' "$_newid"
      rm -f -- "$_bodyfile"
      return 0
    fi
    if _rp_spot_rejected "$(<"$_bodyfile")"; then
      rp::warn "v2 rejected the spot fields (interruptible/bidPerGpu not yet advertised); using the deprecated GraphQL podRentInterruptable bridge — it will be removed once v2 supports spot pods"
      _pod_create_graphql_spot "$obj" "${bid_per_gpu:-}" "$pod_cc"
      rm -f -- "$_bodyfile"
      return 0
    fi
    local _msg
    _msg="$(jq -rc '.error // .message // .title // empty' "$_bodyfile" 2>/dev/null || true)"
    rm -f -- "$_bodyfile"
    _rp_exit_for_status "$_status" "Runpod POST /pods -> HTTP $_status${_msg:+: $_msg}"
  fi

  rp::resource_create pod "" "$obj"
}

# True (0) when a v2 create error body indicates the spot fields were the
# rejected extras — i.e. the server does not yet advertise interruptible/bidPerGpu
# (a 422 from an unevaluatedProperties:false schema, or a similar validation
# message). A non-spot validation error (e.g. bad GPU type) does not mention
# these and so does not trigger the bridge.
_rp_spot_rejected() {
  printf '%s' "$1" | grep -qiE 'interruptible|bidPerGpu|unevaluatedProperties|extra_forbidden|additionalProperties' 2>/dev/null
}

# Spot-pod bridge: v2 rejected the spot fields, so create via the GraphQL
# podRentInterruptable mutation. Translates the v2 request body into that
# mutation's input shape (spot is GPU-only, so it requires a gpu block). This is
# a temporary, deprecated path kept only until REST v2 supports spot natively;
# it dies with the GraphQL error if the bridge itself fails.
_pod_create_graphql_spot() {
  local obj="$1" input q data id
  # $2 is the bid, $3 the cost center to tag the bridged pod into (the bridge
  # bypasses rp::resource_create, so assign-at-create is stamped here).
  [[ "$(printf '%s' "$obj" | jq -r 'has("gpu")')" == "true" ]] ||
    rp::die "spot pods require a GPU (--gpu); CPU spot pods are not supported"
  input="$(printf '%s' "$obj" | jq -c '{
    name: .name,
    imageName: .image,
    templateId: (.templateId // null),
    cloudType: (.cloud // "SECURE"),
    containerDiskInGb: (.disk // null),
    volumeInGb: (if .mounts and .mounts.persistent then .mounts.persistent.size else null end),
    volumeMountPath: (if .mounts and .mounts.persistent then .mounts.persistent.path else null end),
    networkVolumeId: (if .mounts and .mounts.network then .mounts.network.volumeId else null end),
    dataCenterId: (if (.dataCenterIds | length) > 0 then .dataCenterIds[0] else null end),
    ports: (if .ports and (.ports | length) > 0 then (.ports | join(",")) else null end),
    dockerArgs: (.args // null),
    env: (if .env then [ .env | to_entries[] | {key: .key, value: .value} ] else null end),
    containerRegistryAuthId: (.registry // null),
    gpuTypeId: (.gpu.id // null),
    gpuCount: (.gpu.count // null),
    startSsh: (.startSsh // false),
    bidPerGpu: (.bidPerGpu // null)
  }')"
  q='mutation($input: PodRentInterruptableInput!) {
    podRentInterruptable(input: $input) { id imageName }
  }'
  data="$(rp::graphql "$q" "$(rp::json_obj input "$input")")" || return $?
  id="$(printf '%s' "$data" | jq -r '.podRentInterruptable.id')"
  rp::cc_tag_quietly "${3:-}" pod "$id"
  rp::ok "created pod (GraphQL bridge)${name_val:+ '$name_val'}: $id"
  printf '%s\n' "$id"
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
#   --image <ref>                  Docker image reference (required unless
#                                  --template-id is given)
#   --template-id <id>             seed the container config from a template id;
#                                  makes --image optional
#   --name <n>                     pod name (required)
#   --gpu <type>                   GPU type id — see `rp stock gpu` (alias: --gpu-id)
#   --gpu-count N                  GPUs to attach (default: 1)
#   --cpu-flavor <id>              CPU flavour id — see `rp stock cpus`
#   --vcpu N                       vCPUs; a power of two, minimum 2
#   --compute-type GPU|CPU         runpodctl coercion: selects the --gpu path, or
#                                  the --cpu-flavor/--vcpu path (requires the
#                                  matching flags); adds no data of its own
#   --cloud SECURE|COMMUNITY       hardware tier (default: SECURE) (alias: --cloud-type)
#   --dc <id,…>                    preferred datacentres; omit to let the
#                                  scheduler place the pod (alias: --data-center-ids)
#   --volume-gb N                  host-local persistent volume, GB (minimum 10)
#                                  (alias: --volume-in-gb)
#   --network-volume-id <id>       attach an existing network volume instead
#   --volume-path <path>           mount path for either volume kind
#                                  (default: /workspace) (alias: --volume-mount-path)
#   --container-disk-gb N          ephemeral container disk, GB (minimum 1)
#                                  (alias: --container-disk-in-gb)
#   --global-networking true|false give the pod a private IP reachable across
#                                  datacentres; omit for the API default (false)
#   --public-ip                    request a public IP; community-cloud pods are
#                                  not publicly routable by default, so set this
#                                  to reach them directly (alias of runpodctl's
#                                  --public-ip; maps to supportPublicIp)
#   --ports <a/b,…>                exposed ports, each as port/protocol
#   --env K=V                      environment variable; repeatable; NOT aliased to runpodctl's --env (a single JSON object) — the repeatable K=V shapes differ
#   --start-cmd <a,b,…>            arguments passed to the container entrypoint
#                                  (alias: --docker-args)
#   --template <id>                template whose container config seeds the pod
#   --registry <id>                registry credential for a private image
#                                  (alias: --registry-auth-id)
#   --ssh                          start the pod with runpodctl-style SSH
#                                  access enabled (requires registered SSH keys)
#   --min-cuda-version <x.y>       require a GPU driver with at least this CUDA
#                                  version (e.g. 12.1); GPU pods only
#   --cost-center <name>           tag the pod into a local cost center at
#                                  create (see: rp cost-center); the center must
#                                  already exist
#   --interruptible                 create a spot (interruptible) pod; the server
#                                  bids the on-demand price unless --bid-per-gpu
#                                  is also set (GPU pods only)
#   --bid-per-gpu <n>               max $/GPU-hour to pay for a spot pod; implies
#                                  --interruptible; must be > 0 (GPU pods only)
#
# Notes:
#   A pod is either a GPU pod or a CPU pod: pass --gpu or --cpu-flavor, never
#   both. The CLI enforces "exactly one": it rejects a create that sets neither
#   or that sets both, so the failure is a local usage error, not an API error.
#   --name is required by the API and checked by the CLI up front, so a missing
#   --name fails locally before any request.
#   --image is required even with --template, and always wins over the
#   template's own image. --template-id is the v2-native equivalent: pass the
#   template id directly and the API applies its container config, which lets you
#   omit --image entirely.
#   Storage is one kind or the other: --volume-gb is host-local, pinned to the
#   machine and lost if that host fails, whilst --network-volume-id is durable
#   and must already live in the pod's datacentre. CPU pods reject --volume-gb.
#   The mount kind is fixed at create — `rp pod update` cannot switch it.
#   --compute-type is runpodctl's spelling for the same choice: `--compute-type
#   GPU --gpu <t>` and `--compute-type CPU --cpu-flavor <id> --vcpu <n>` are
#   equivalent to the canonical rp invocations; it carries no data and dies if
#   the matching flags are absent.
#   --gpu takes a single type in v2. A comma-separated list is still accepted,
#   but only the first entry is used and a warning is printed.
#   --global-networking needs an NVIDIA GPU and a datacentre that supports it,
#   so it is rejected alongside --cpu-flavor.
#   v2 has no templateId parameter. --template fetches the template and spreads
#   its container config as defaults.
#   --interruptible and --bid-per-gpu create a spot pod: --bid-per-gpu sets the
#   maximum $/GPU-hour you will pay and implies --interruptible; given alone,
#   --interruptible bids the on-demand price. Both are GPU-only — a spot pod is
#   preempted when capacity is reclaimed, so checkpoint long work. The bid must
#   be a positive number. The request is sent to REST v2 first; if that server
#   does not yet advertise the spot fields it falls back to the deprecated
#   GraphQL podRentInterruptable mutation, warning as it does so. The bridge is
#   temporary and will be removed once v2 supports spot pods natively.
#   --min-cuda-version is a GPU-only field: a value not matching X.Y (e.g. 12.1)
#   is rejected up front, and a valid value is applied only to GPU pods — on a
#   CPU pod it is silently ignored (there is no gpu block to carry it). It is
#   mutually exclusive with any allowed-CUDA-versions selection, which rp does
#   not expose.
#   --force is accepted and ignored. Unlike `rp volume create` and
#   `rp template create`, pod creation is not idempotent by name, so re-running
#   this command creates a second pod.
#   --cost-center tags the new pod into a local cost center for per-project
#   spend (`rp cost-center spend`); the center must exist, and the check runs
#   before the pod is created. The tagging is local — Runpod's own Cost Centers
#   are console-only.
#
# Examples:
# # Create a GPU pod from the PyTorch image
# $ rp pod create --name trainer --image runpod/pytorch:2.2.0 \
#     --gpu "NVIDIA GeForce RTX 4090" --container-disk-gb 50
# # Create a CPU-only pod
# $ rp pod create --name cpu-box --image alpine --cpu-flavor cpu5c --vcpu 4
# # Attach a network volume to a GPU pod
# $ rp pod create --name shared --image alpine --gpu "NVIDIA L4" \
#     --network-volume-id vol_xyz --volume-path /runpod-volume
# # Create a spot pod with a per-GPU bid
# $ rp pod create --name spot-trainer --image runpod/pytorch:2.2.0 \
#     --gpu "NVIDIA RTX 4090" --bid-per-gpu 0.20
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
#   --public-ip      show only pods that currently expose a public IP
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
#                                  (alias: --container-disk-in-gb)
#   --volume-gb N                  resize the host-local persistent volume, GB
#                                  (alias: --volume-in-gb)
#   --volume-path <path>           mount path (default: /workspace)
#                                  (alias: --volume-mount-path)
#   --ports <a/b,…>                exposed ports, each as port/protocol
#   --env K=V                      environment variable; repeatable; NOT aliased to runpodctl's --env (a single JSON object) — the repeatable K=V shapes differ
#   --start-cmd <a,b,…>            arguments passed to the container entrypoint
#                                  (alias: --docker-args)
#   --registry <id>                registry credential for a private image
#                                  (alias: --registry-auth-id)
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
# # Rename the pod
# $ rp pod update pod_abc123 --name renamed
# # Grow the container disk and set an env var
# $ rp pod update pod_abc123 --container-disk-gb 80 --env HF_TOKEN=xxx
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
# # Show the full container log from the start
# $ rp pod logs pod_abc123 --tail 0
# # Show the last 500 system-log lines
# $ rp pod logs pod_abc123 --source system --tail 500
#
# API: GET /v2/pods/{id}/logs

_pod_list() {
  local body arr jqf
  body="$(rp::http GET /pods)"
  arr="$(rp::unwrap pods "$body")"
  # --public-ip keeps only pods that currently expose a public IP (the
  # community-cloud concern from the upstream request): the pod record's
  # publicIp is empty while initialising and absent once terminated.
  if rp::args_has public-ip; then
    arr="$(printf '%s' "$arr" | jq -c 'map(select((.publicIp // "") != ""))')" ||
      rp::die "public-ip filter failed"
  fi
  jqf="$(rp::args_get jq)"
  [[ -z "$jqf" ]] || arr="$(printf '%s' "$arr" | jq -c "$jqf")" || rp::die "invalid --jq filter: $jqf"
  rp::paginate arr
  rp::emit_json_or "$arr" rp::table "$arr" id name image status cost publicIp
}

rp::cmd_pod() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _pod_create ;;
  list) _pod_list ;;
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
   create --image <img> [--name <n>] [--gpu <id> (alias: --gpu-id)] [--gpu-count N]
           [--compute-type GPU|CPU (runpodctl coercion: --gpu, or --cpu-flavor+--vcpu)]
           [--dc <id,id> (alias: --data-center-ids)] [--cpu-flavor <id>] [--vcpu <n>]
           (CPU-only pod: --cpu-flavor excludes --gpu and --volume-gb)
           [--cloud SECURE|COMMUNITY (alias: --cloud-type)]
           [--network-volume-id <id>] [--volume-gb N (alias: --volume-in-gb)]
           [--container-disk-gb N (alias: --container-disk-in-gb)]
           [--volume-path <p> (alias: --volume-mount-path)]
           [--global-networking true|false] [--ports <a/b,...>]
           [--env K=V]…  (--env is repeatable K=V; NOT aliased to runpodctl's JSON --env)
              [--start-cmd <a,b,...> (alias: --docker-args)] [--template <id>] [--template-id <id>]
              [--registry <id> (alias: --registry-auth-id)] [--ssh] [--min-cuda-version <x.y>]
              [--interruptible] [--bid-per-gpu <n>]  (spot pod; --bid-per-gpu implies --interruptible)
              [--cost-center <name>]  (tag into a local cost center at create; see rp cost-center)
   update <id> [--container-disk-gb N (alias: --container-disk-in-gb)]
           [--volume-gb N (alias: --volume-in-gb)] [--volume-path <p> (alias: --volume-mount-path)]
           [--name <n>] [--image <img>] [--global-networking true|false] [--locked true|false]
           [--ports <a/b,...>] [--env K=V]… (--env is repeatable K=V; NOT aliased to runpodctl's JSON --env)
           [--start-cmd <a,b,...> (alias: --docker-args)]
           [--registry <id> (alias: --registry-auth-id)]   (PATCH; resets a running pod)
   list [--public-ip] [--limit N] [--cursor <c>] [--jq <filter>] | get <id> | start|stop|restart <id> | logs <id> | delete <id>   (reset is an alias for restart; v2 dropped it)
   logs <id> [--source container|system] [--tail N] [--since <rfc3339>] [--last-event-id <ts>]   (live SSE stream; --tail 0 = live only)
EOF
    ;;
  *) rp::usage "unknown pod verb: '$verb'" ;;
  esac
}
