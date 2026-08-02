#!/usr/bin/env bash
#
# Network volume lifecycle, model sync, and GPU stock lookup.
#
# A network volume is durable storage pinned to one datacentre, mountable by
# pods and serverless endpoints and outliving all of them. The CRUD verbs take
# a volume id; the data-plane verbs (sync, ls, gpus) take a name and resolve it
# for you. File transfer rides the S3-compatible API, which only some
# datacentres expose.
#
# Usage: rp volume <verb> [flags]
#

# `rp volume sync --models <slug>` -> HuggingFace repo slug. Any `owner/repo`
# slug is accepted verbatim (no curated alias list, so the CLI stays
# workload-agnostic); reject anything that is not a well-formed slug. A case
# rather than an associative array: the test harnesses source this file from
# inside a function, where `declare -A` without -g would scope the array away.
_model_repo() {
  [[ "$1" == */* ]] || return 1
  printf '%s' "$1"
}

_volume_create() {
  local name size dc vtype
  name="$(rp::args_get name)"
  size="$(rp::args_get_uint size)"
  dc="$(rp::args_get dc)"
  [[ -n "$name" && -n "$size" && -n "$dc" ]] || rp::usage "usage: rp volume create --name <n> --size <gb> --dc <id> [--type STANDARD|HIGH_PERFORMANCE]"
  vtype="$(rp::args_get type)"
  case "${vtype^^}" in
  '' | STANDARD | HIGH_PERFORMANCE) vtype="${vtype^^}" ;;
  *) rp::usage "--type must be STANDARD or HIGH_PERFORMANCE (got: '$vtype')" ;;
  esac
  rp::warn_unless_s3_dc "$dc"
  local body='{}'
  rp::obj_set body name "$(rp::json_str "$name")"
  rp::obj_set body size "$size"
  rp::obj_set body dataCenter "$(rp::json_str "$dc")"
  [[ -z "$vtype" ]] || rp::obj_set body type "$(rp::json_str "$vtype")"
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
  size="$(rp::args_get_uint size)"
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
  rp::require_pos name "usage: rp volume sync <name> [--source <dir> | --models <owner/repo>,...] [--prefix models]"
  rp::volume_dc "$name"
  local id="$RP_VOLUME_ID" dc="$RP_VOLUME_DC"
  rp::is_s3_dc "$dc" || rp::usage "volume's datacenter '$dc' is not S3-API supported (see: rp stock dc)"
  local prefix source models
  prefix="$(rp::args_get prefix "$RP_DEFAULT_MODEL_PREFIX")"
  source="$(rp::args_get source)"
  models="$(rp::args_get models)"
  if [[ -n "$source" ]]; then
    [[ -d "$source" ]] || rp::notfound "source dir not found: $source"
    rp::info "syncing $source -> $name (s3://$id/$prefix, dc=$dc)"
    rp::s3_sync "$source" "$id" "$dc" "$prefix"
    rp::ok "synced $source -> $name"
    return 0
  fi
  [[ -n "$models" ]] || rp::usage "provide --source <dir> or --models <owner/repo>,..."
  rp::require_cmd huggingface-cli
  local cache
  cache="${RP_MODEL_CACHE:-$RP_DEFAULT_MODEL_CACHE}"
  mkdir -p "$cache"
  local -a ms
  mapfile -t ms < <(rp::split_csv "$models")
  local m repo
  for m in "${ms[@]}"; do
    repo="$(_model_repo "$m")" || rp::usage "invalid model repo: $m (expected owner/repo, e.g. meta-llama/Llama-3-8B)"
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
    wantjson="$(rp::csv_to_jsonarray "$filter")"
    data="$(printf '%s' "$data" | jq --argjson want "$wantjson" 'map(select(.id as $id | $want | index($id)))')"
  fi
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({GPU:.id, VRAM_GB:(.memory//0), STOCK:(.availability//""), SECURE_PRICE:(.price.secure//"")})' \
    GPU VRAM_GB STOCK SECURE_PRICE
}

###
### :::: documentation (rp doc volume) :::: ###################################
###

# doc: list
# List your network volumes as a table: id, name, size, dataCenter.
#
# Usage: rp volume list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      return at most N volumes
#   --cursor <c>   offset to resume from; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# Notes:
#   dataCenter is where the volume lives for good. A volume cannot move, so
#   anything that mounts it must be scheduled in that same datacentre.
#   size is the provisioned capacity in GB, not the space in use. Billing
#   follows the provisioned figure.
#   Paging is client-side: the whole list is fetched, then sliced. When output
#   is truncated the next cursor is printed to stderr, leaving stdout clean.
#
# API: GET /v2/network-volumes

# doc: get
# Show one network volume's full record.
#
# Usage: rp volume get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>           network volume id — from `rp volume list`
#
# Options:
#   --jq <filter>  jq filter applied to the record
#   --json         print the raw API response instead of pretty JSON
#
# Notes:
#   This verb takes an id, not a name. The data-plane verbs (`sync`, `ls`,
#   `gpus`) are the ones that accept a name and resolve it for you.
#   The record carries the storage tier chosen at create, which no other verb
#   can change.
#
# API: GET /v2/network-volumes/{id}

# doc: create
# Create a network volume in a datacentre.
#
# Usage: rp volume create --name <n> --size <gb> --dc <id>
#                         [--type STANDARD|HIGH_PERFORMANCE] [--force]
#
# Options:
#   --name <n>                        volume name (required)
#   --size <gb>                       capacity in GB, 10–4096 (required)
#   --dc <id>                         datacentre id (required) — see
#                                     `rp stock dc`
#   --type STANDARD|HIGH_PERFORMANCE  storage tier (default: STANDARD)
#   --force                           create even when the name is taken
#
# Notes:
#   Creation is idempotent by name: where a volume of that name already
#   exists, the CLI prints its id and skips the POST. --force sends the
#   request regardless, which is how you end up with two volumes sharing a
#   name.
#   --dc fixes the volume's home. It cannot be moved afterwards, and a pod or
#   endpoint that mounts it must be placed in the same datacentre.
#   Only some datacentres expose the S3 API. Creating in one that does not is
#   allowed but prints a warning, because `rp volume sync` and `rp volume ls`
#   will not work there. `rp stock dc` marks the ones that do.
#   --type is matched case-insensitively and checked locally; anything other
#   than STANDARD or HIGH_PERFORMANCE is a usage error. The tier is immutable,
#   so `rp volume update` cannot change it later.
#   --size is not range-checked here. The API enforces 10–4096 GB and returns
#   its own error outside that range.
#   The new id is printed on stdout and the confirmation on stderr, so
#   `id=$(rp volume create …)` captures just the id.
#
# Examples:
#   rp volume create --name models --size 500 --dc EU-RO-1
#   rp volume create --name fast --size 100 --dc US-KS-2 \
#     --type HIGH_PERFORMANCE
#
# API: POST /v2/network-volumes

# doc: update
# Rename a network volume, or grow it.
#
# Usage: rp volume update <id> [--name <n>] [--size <gb>] [--json]
#
# Arguments:
#   <id>         network volume id — from `rp volume list`
#
# Options:
#   --name <n>   rename the volume
#   --size <gb>  new capacity in GB; may only grow
#   --json       print the raw API response
#
# Notes:
#   At least one of --name or --size is required; with neither, the command
#   exits with a usage error rather than sending an empty PATCH.
#   Capacity only grows. The API rejects a size below the current one and
#   there is no shrink path — copy elsewhere and recreate instead.
#   name and size are the only fields the API accepts here. The datacentre and
#   the storage tier are both fixed at create.
#   This verb takes an id, not a name; `rp volume list` prints both.
#
# Examples:
#   rp volume update netvol_abc123 --name archive
#   rp volume update netvol_abc123 --size 1000
#
# API: PATCH /v2/network-volumes/{id}

# doc: delete
# Delete a network volume permanently.
#
# Usage: rp volume delete <id>
#
# Arguments:
#   <id>  network volume id — from `rp volume list`
#
# Notes:
#   Deletion is irreversible and takes the volume's contents with it. There is
#   no stop-and-keep state as there is for a pod.
#   A volume still mounted by a pod cannot be deleted. Terminate the pod, or
#   recreate it without the mount, first.
#   The command prints a confirmation line and nothing else: the response body
#   is discarded, so there is no --json output here.
#
# API: DELETE /v2/network-volumes/{id}

# doc: sync
# Upload a local directory or Hugging Face models to a volume.
#
# Usage: rp volume sync <name> (--source <dir> | --models <owner/repo,…>)
#                       [--prefix <p>]
#
# Arguments:
#   <name>                   network volume name — from `rp volume list`
#
# Options:
#   --source <dir>           local directory to upload
#   --models <owner/repo,…>  Hugging Face repo slugs to fetch, then upload
#   --prefix <p>             key prefix inside the volume (default: models)
#
# Notes:
#   Give one source or the other. With neither, the command exits with a usage
#   error; with both, --source wins and --models is ignored silently.
#   The volume's datacentre must expose the S3 API or the command refuses to
#   run. `rp stock dc` marks which datacentres qualify.
#   Transfer is `aws s3 sync`, so the aws CLI must be installed and
#   RUNPOD_S3_ACCESS_KEY and RUNPOD_S3_SECRET_KEY must be set. Those are S3 API
#   keys from the console, not your Runpod API key. The read timeout is raised
#   to 7200 seconds so large transfers survive.
#   The two sources lay out differently: --source copies a directory's
#   contents to <prefix>/, whilst --models places each repo under
#   <prefix>/<owner>/<repo>/.
#   --models needs huggingface-cli and downloads to a local cache first —
#   $RP_MODEL_CACHE, or .cache/models under the rp install. Any well-formed
#   owner/repo slug is accepted; there is no curated list.
#   Being a sync, a re-run transfers only what changed and deletes nothing
#   already on the volume.
#   Progress is the aws CLI's own output, so there is no --json.
#
# Examples:
#   rp volume sync models --source ./checkpoints --prefix runs/2026-08
#   rp volume sync models --models meta-llama/Llama-3-8B,google/gemma-2b
#
# API: GET /v2/network-volumes/{id}, then `aws s3 sync` to s3api-<dc>.runpod.io

# doc: ls
# List the objects stored on a network volume.
#
# Usage: rp volume ls <name> [--path <remote-path>]
#
# Arguments:
#   <name>                network volume name — from `rp volume list`
#
# Options:
#   --path <remote-path>  key prefix to list; omit for the volume root
#
# Notes:
#   This is `aws s3 ls` against the volume's S3 endpoint, so it needs the aws
#   CLI and the RUNPOD_S3_ACCESS_KEY / RUNPOD_S3_SECRET_KEY pair. The listing
#   is printed verbatim, which is why there is no --json.
#   The listing is one level deep: sub-prefixes show as PRE entries rather
#   than being expanded. Pass --path to descend into one.
#   Unlike `rp volume sync`, this does not check that the datacentre supports
#   the S3 API beforehand, so a volume outside those datacentres fails inside
#   aws rather than with a clear message.
#
# Examples:
#   rp volume ls models
#   rp volume ls models --path models/meta-llama
#
# API: GET /v2/network-volumes/{id}, then `aws s3 ls` on s3api-<dc>.runpod.io

# doc: gpus
# List GPU types in stock, with the volume's datacentre noted.
#
# Usage: rp volume gpus <name> [--gpu <id,…>] [--json]
#
# Arguments:
#   <name>        network volume name — from `rp volume list`
#
# Options:
#   --gpu <id,…>  restrict the table to these GPU type ids
#   --json        print the raw API response
#
# Notes:
#   The catalogue is account-wide, not per-datacentre: v2 exposes no per-DC
#   stock field. The command prints the volume's datacentre for context and
#   then the same figures `rp stock gpu` shows, so read the table as "what is
#   in stock at all", not "what is in stock beside this volume".
#   Columns are GPU, VRAM_GB, STOCK and SECURE_PRICE. SECURE_PRICE is the
#   secure-cloud rate per GPU per hour; community pricing is not shown.
#   The catalogue is queried for POD and SERVERLESS together, so a type listed
#   here may still be unavailable for one of the two.
#   --gpu filters client-side after the fetch, so an id that matches nothing
#   yields an empty table rather than an error.
#
# Examples:
#   rp volume gpus models
#   rp volume gpus models --gpu "NVIDIA L4,NVIDIA GeForce RTX 4090"
#
# API: GET /v2/catalog/gpus  (include=AVAILABILITY, product=POD,SERVERLESS)

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
  create --name <n> --size <gb> --dc <id> [--type STANDARD|HIGH_PERFORMANCE]   (idempotent by name; warns if DC is not S3-capable; tier is immutable)
  list | get <id> | update <id> [--name <n>] [--size <gb>] | delete <id>
  sync <name> --source <dir> | --models <owner/repo>,...  [--prefix models]
  ls <name> [--path <remote-path>]
  gpus <name> [--gpu <id,id>]   (account-wide availability for this NV's datacenter)
EOF
    ;;
  *) rp::usage "unknown volume verb: '$verb'" ;;
  esac
}
