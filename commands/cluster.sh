#!/usr/bin/env bash
#
# Clusters: multi-node homogeneous pod fleets (REST v2).
#
# A cluster is a single named, single-datacentre fleet of identical pods — every
# member shares one compute shape (GPU type, GPUs per pod, pod count) and one
# container config. Create provision the whole fleet; rename is the only mutable
# field afterwards, so compute, type, and container config are fixed at create.
# The v2 REST plane backs every verb here (no GraphQL equivalent).
#
# Usage: rp cluster <verb> [flags]
#

_cluster_create() {
  local name type gpu pod_count gpu_count
  name="$(rp::args_get name)"
  [[ -n "$name" ]] || rp::usage "usage: rp cluster create --name <n> --type <kind> --gpu <type> [--pod-count N] [--gpu-count N] [flags]"
  type="$(rp::args_get type)"
  type="${type^^}"
  case "$type" in
  APPLICATION | TRAINING | SLURM | RAY) ;;
  *) rp::usage "usage: rp cluster create --type must be APPLICATION|TRAINING|SLURM|RAY (got: '$type')" ;;
  esac
  gpu="$(rp::args_get gpu)"
  [[ -n "$gpu" ]] || rp::usage "usage: rp cluster create --type <kind> --gpu <type> (a cluster is homogeneous: one GPU type for every pod)"

  # compute is required and fully specified: gpuCountPerPod >= 1, podCount >= 2.
  pod_count="$(rp::args_get_uint pod-count 2)"
  ((pod_count >= 2)) || rp::usage "usage: rp cluster create --pod-count must be >= 2 (a cluster has at least two nodes)"
  gpu_count="$(rp::args_get_uint gpu-count "$RP_DEFAULT_GPU_COUNT")"
  ((gpu_count >= 1)) || rp::usage "usage: rp cluster create --gpu-count must be >= 1"
  local compute
  compute="$(rp::json_obj gpuTypeId "$(rp::json_str "$gpu")" gpuCountPerPod "$gpu_count" podCount "$pod_count")"

  local obj='{}'
  rp::obj_set obj name "$(rp::json_str "$name")"
  rp::obj_set obj type "$(rp::json_str "$type")"
  rp::obj_set obj compute "$compute"

  local image
  image="$(rp::args_get image)"
  [[ -z "$image" ]] || rp::obj_set obj image "$(rp::json_str "$image")"

  local disk
  disk="$(rp::args_get_uint container-disk-gb)"
  rp::obj_set obj disk "$disk"

  local ports
  ports="$(rp::args_get ports)"
  [[ -z "$ports" ]] || rp::obj_set obj ports "$(rp::csv_to_jsonarray "$ports")"

  local env
  env="$(rp::args_get env)"
  [[ -z "$env" ]] || rp::obj_set obj env "$(rp::env_to_json "$env")"

  local start
  start="$(rp::args_get start-cmd)"
  [[ -z "$start" ]] || rp::obj_set obj args "$(rp::json_str "$(rp::csv_to_argstring "$start")")"

  local dc
  dc="$(rp::args_get dc)"
  [[ -z "$dc" ]] || rp::obj_set obj dataCenterIds "$(rp::csv_to_jsonarray "$dc")"

  local nv mpath
  nv="$(rp::args_get network-volume-id)"
  if [[ -n "$nv" ]]; then
    mpath="$(rp::args_get volume-path)"
    rp::obj_set obj mounts "$(rp::json_obj network "$(rp::json_array "$(rp::json_obj volumeId "$(rp::json_str "$nv")" path "$(rp::json_str "${mpath:-$RP_DEFAULT_MOUNT_PATH}")")")")"
  fi

  local tmpl
  tmpl="$(rp::args_get template-id)"
  [[ -z "$tmpl" ]] || rp::obj_set obj templateId "$(rp::json_str "$tmpl")"

  local ssh jup
  rp::require_bool ssh start-ssh
  rp::obj_set obj startSsh "$ssh"
  rp::require_bool jup start-jupyter
  rp::obj_set obj startJupyter "$jup"

  rp::resource_create cluster "$name" "$obj"
}

_cluster_update() {
  local id
  rp::require_pos id "usage: rp cluster update <id> --name <n>"
  local name
  name="$(rp::args_get name)"
  [[ -n "$name" ]] || rp::usage "usage: rp cluster update <id> --name <n> (rename only; compute/type/config are fixed at create)"
  _resource_meta cluster
  local res
  res="$(rp::http PATCH "$RP_RES_PATH/$id" "$(rp::json_obj name "$(rp::json_str "$name")")")"
  rp::emit_json_or "$res" rp::ok "renamed cluster $id"
}

###
### :::: documentation (rp doc cluster) :::: ##################################
###

# doc: list
# List your clusters: id, name, type, node count, created date.
#
# Usage: rp cluster list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      return at most N clusters
#   --cursor <c>   offset to resume from; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# Notes:
#   node count is the cluster's podCount (the homogeneous fleet size), not the
#   number currently provisioned — see `rp cluster pods <id>` for live counts.
#
# API: GET /v2/clusters

# doc: get
# Show one cluster's full record, including its compute shape and member summary.
#
# Usage: rp cluster get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>             cluster id — from `rp cluster list`
#
# Options:
#   --jq <filter>    jq filter applied to the record
#   --json           print the raw API response instead of pretty JSON
#
# API: GET /v2/clusters/{id}

# doc: create
# Provision a homogeneous multi-node cluster.
#
# Usage: rp cluster create --name <n> --type <kind> --gpu <type>
#                         [--pod-count N] [--gpu-count N] [flags]
#
# Options:
#   --name <n>                        cluster name (required)
#   --type <kind>                     APPLICATION|TRAINING|SLURM|RAY (required)
#   --gpu <type>                      one GPU type for every pod (required)
#   --gpu-count N                     GPUs per pod (default: 1; minimum 1)
#   --pod-count N                     number of pods (minimum 2, default: 2)
#   --dc <id,…>                       preferred datacentres; omit to let the
#                                    scheduler place the cluster (single DC)
#   --image <ref>                     Docker image for every pod
#   --container-disk-gb N             ephemeral container disk, GB (minimum 1)
#   --ports <a/b,…>                   exposed ports, each as port/protocol
#   --env K=V                         environment variable; repeatable
#   --start-cmd <a,b,…>               arguments passed to the container entrypoint
#   --network-volume-id <id>          attach one network volume to every pod
#   --volume-path <path>              mount path for the network volume
#   --template-id <id>                seed container config from a template id
#   --start-ssh true|false            provision SSH with your account key
#   --start-jupyter true|false       start Jupyter on every member pod
#   --force                           create even when the name is taken
#
# Notes:
#   A cluster is homogeneous: every pod is identical, so a single --gpu type,
#   --gpu-count, and --pod-count describe the whole fleet. --pod-count must be at
#   least 2 (a cluster is multi-node by definition).
#   Creation is idempotent by name, like `rp volume create` and
#   `rp serverless create`: where a cluster of that name already exists, the CLI
#   prints its id and skips the POST. --force sends the request regardless.
#   Only the name can change afterwards — `rp cluster update` is a rename, and
#   compute shape, type, and container config are fixed at create.
#   Clusters do not yet support private registries (no --registry): the v2
#   create request has no registry field. Use a public image or a network volume
#   for your build.
#   --template-id seeds the container config as defaults; any explicit flag value
#   still wins, and the template's id is recorded on the cluster.
#
# Examples:
# # Create a 4-node H100 training cluster
# $ rp cluster create --name tr-1 --type TRAINING \
#       --gpu "NVIDIA H100 80GB HBM3" --pod-count 4 --gpu-count 8
# # Create a Ray cluster with an attached volume
# $ rp cluster create --name ray --type RAY --gpu "NVIDIA L4" \
#       --image runpod/ray:latest --network-volume-id vol_xyz
#
# API: POST /v2/clusters

# doc: update
# Rename a cluster.
#
# Usage: rp cluster update <id> --name <n>
#
# Arguments:
#   <id>             cluster id — from `rp cluster list`
#
# Options:
#   --name <n>       new cluster name (required)
#   --json           print the raw API response
#
# Notes:
#   Rename is the only mutable field. Compute shape, type, and container config
#   are fixed at create and cannot be changed here.
#
# API: PATCH /v2/clusters/{id}

# doc: delete
# Delete a cluster and tear down its member pods.
#
# Usage: rp cluster delete <id>
#
# Arguments:
#   <id>             cluster id — from `rp cluster list`
#
# Notes:
#   Deletion is irreversible; every member pod is destroyed with the cluster.
#
# API: DELETE /v2/clusters/{id}

# doc: pods
# List a cluster's member pods as a table: id, name, status.
#
# Usage: rp cluster pods <id> [--json]
#
# Arguments:
#   <id>             cluster id — from `rp cluster list`
#
# Options:
#   --json           print the raw API response (full pod records)
#
# Notes:
#   The list endpoint returns the full pod objects (same shape as `rp pod get`),
#   so this is a quick fleet view. `rp cluster get <id>` carries the lightweight
#   member summary (total + counts by status).
#
# API: GET /v2/clusters/{id}/pods

# doc: pods-add
# Scale out a running cluster by adding more pods.
#
# Usage: rp cluster pods add <id> --pod-count N
#
# Arguments:
#   <id>             cluster id — from `rp cluster list`
#
# Options:
#   --pod-count N    number of additional pods to add (minimum 1, required)
#   --json           print the raw API response
#
# Notes:
#   New pods join the cluster's private network automatically and inherit the
#   existing nodes' GPU type, template, and network storage, matching the
#   cluster's homogeneous shape. Scaling is unavailable for clusters on reserved
#   or contracted hardware.
#   The request sends the number of pods to add; `podCount` is the same field
#   used by `rp cluster create`, here repurposed for scale-out.
#
# API: POST /v2/clusters/{id}/pods

rp::cmd_cluster() {
  local verb="${1:-help}"
  shift || true
  if [[ "$verb" == "pods" ]]; then
    _cluster_pods "$@"
    return
  fi
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list cluster --reshape 'map({id, name, type, pods:.pods.count, createdAt})' id name type pods createdAt ;;
  get) rp::resource_get cluster ;;
  create) _cluster_create ;;
  update) _cluster_update ;;
  delete) rp::resource_delete cluster ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp cluster <verb> [flags]
  create --name <n> --type <kind> --gpu <type> [--pod-count N] [--gpu-count N]
         [--dc <id,..>] [--image <ref>] [--container-disk-gb N] [--ports a/b]
         [--env K=V] [--start-cmd a,b] [--network-volume-id <id>] [--volume-path <p>]
         [--template-id <id>] [--start-ssh true|false] [--start-jupyter true|false]
         [--force]   (idempotent by --name; only --name is mutable afterwards)
  list | get <id> | update <id> --name <n> | delete <id> | pods <id> | pods add <id> --pod-count N
EOF
    ;;
  *) rp::usage "unknown cluster verb: '$verb'" ;;
  esac
}

_cluster_pods() {
  local sub="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && sub=help
  case "$sub" in
  add) _cluster_pods_add ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp cluster pods <id> [flags]
  <id>                      list a cluster's member pods (id, name, status)
  add <id> --pod-count N    scale out: add N (>= 1) more pods to a running cluster
EOF
    ;;
  *)
    # No sub-verb: the argument is the cluster id; list its member pods.
    _cluster_pods_list "$sub"
    ;;
  esac
}

_cluster_pods_list() {
  local id="$1"
  rp::require_id id "$id" "cluster id"
  _resource_meta cluster
  local body
  body="$(rp::http GET "$RP_RES_PATH/$id/pods")"
  local arr
  arr="$(rp::unwrap pods "$body")"
  rp::emit_json_or "$body" rp::table "$arr" id name status
}

# Scale out a running cluster by adding more pods. New pods inherit the
# cluster's homogeneous shape (GPU type, template, network storage) and join
# its private network automatically. The request body carries the number of
# additional pods to add.
_cluster_pods_add() {
  local id
  rp::require_pos id "usage: rp cluster pods add <id> --pod-count N"
  rp::require_id id "$id" "cluster id"
  local pod_count
  pod_count="$(rp::args_get_uint pod-count)"
  [[ -n "$pod_count" ]] || rp::usage "usage: rp cluster pods add <id> --pod-count N is required (number of additional pods to add)"
  ((pod_count >= 1)) || rp::usage "usage: rp cluster pods add <id> --pod-count must be >= 1 (number of additional pods to add)"
  _resource_meta cluster
  local body res
  body="$(rp::json_obj podCount "$pod_count")"
  res="$(rp::http POST "$RP_RES_PATH/$id/pods" "$body")"
  rp::emit_json_or "$res" rp::ok "added $pod_count pod(s) to cluster $id"
}
