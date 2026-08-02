#!/usr/bin/env bash
#
# Reusable container configuration for pods and endpoints.
#
# A template is a saved container config — image, entrypoint arguments, ports,
# environment, disk — that `rp pod create --template` and the serverless create
# paths spread as their defaults. Each one is either a pod template or a
# serverless template, and the serverless kind takes no persistent volume.
# Templates are private until you publish one with --public true.
#
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

###
### :::: documentation (rp doc template) :::: #################################
###

# doc: list
# List your templates as a table: id, name, image, serverless.
#
# Usage: rp template list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N        return at most N templates
#   --cursor <c>     offset to resume from; pairs with --limit
#   --jq <filter>    jq filter applied to the array
#   --json           print the raw API response
#
# Notes:
#   serverless marks the kind: true for a serverless template, false for a pod
#   template.
#   Category and visibility have no column here; read them with
#   `rp template get`.
#   Paging is client-side: the whole list is fetched, then sliced. When output
#   is truncated the next cursor is printed to stderr, leaving stdout clean.
#
# API: GET /v2/templates

# doc: get
# Show one template's full record, including its container config.
#
# Usage: rp template get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>             template id — from `rp template list`
#
# Options:
#   --jq <filter>    jq filter applied to the record
#   --json           print the raw API response instead of pretty JSON
#
# Notes:
#   The record carries the container config that `rp pod create --template`
#   spreads: image, args, disk, ports, env and registry.
#   This verb takes an id, not a name; find the id with `rp template search`.
#
# API: GET /v2/templates/{id}

# doc: create
# Create a template from an image and a container config.
#
# Usage: rp template create --name <n> --image <img> [flags]
#
# Options:
#   --name <n>                template name (required)
#   --image <img>             Docker image reference (required)
#   --serverless              build a serverless template rather than a pod one
#   --category CPU|NVIDIA|AMD hardware family the template targets
#                             (default: NVIDIA)
#   --public true|false       publish the template; omit for the API default
#                             (false)
#   --docker-cmd <a,b,…>      arguments passed to the container entrypoint
#   --env K=V                 environment variable; repeatable
#   --ports <a/b,…>           exposed ports, each as port/protocol
#   --container-disk-gb N     ephemeral container disk, GB
#   --volume-gb N             persistent volume mounted at /workspace, GB
#   --registry <id>           registry credential for a private image
#   --force                   create even when a template of this name exists
#
# Notes:
#   --name and --image are both required, and the CLI checks for both before
#   sending the request.
#   Create is idempotent by name: without --force, a template already carrying
#   this name is not recreated — its id is printed and no POST is sent.
#   --serverless is a bare flag, so it can only turn the serverless kind on.
#   --volume-gb is ignored with a warning when --serverless is set: serverless
#   templates reject a volume mount. There is no --volume-path either — a
#   template's mount path is fixed at /workspace.
#   --public is tri-state: omitting it leaves the key out of the body, so the
#   API applies its own default and the template stays private.
#   --category is checked locally against CPU|NVIDIA|AMD before the request.
#   --docker-cmd is joined with spaces into v2's single `args` string; v1 took
#   an array.
#   The new id is printed on stdout and the confirmation goes to stderr, so
#   `id=$(rp template create …)` captures just the id.
#
# Examples:
#   rp template create --name torch-base --image runpod/pytorch:2.2.0 \
#     --container-disk-gb 20 --env HF_HOME=/workspace/hf
#   rp template create --name infer --image myrepo/infer:1 --serverless \
#     --registry reg_abc123
#
# API: POST /v2/templates

# doc: update
# Change a template's fields in place.
#
# Usage: rp template update <id> [flags]
#
# Arguments:
#   <id>                      template id — from `rp template list`
#
# Options:
#   --name <n>                rename the template
#   --image <img>             Docker image reference
#   --serverless              mark the template as a serverless template
#   --category CPU|NVIDIA|AMD hardware family the template targets
#   --public true|false       publish or unpublish; omit to leave it unchanged
#   --docker-cmd <a,b,…>      arguments passed to the container entrypoint
#   --env K=V                 environment variable; repeatable
#   --ports <a/b,…>           exposed ports, each as port/protocol
#   --container-disk-gb N     ephemeral container disk, GB
#   --volume-gb N             persistent volume mounted at /workspace, GB
#   --registry <id>           registry credential for a private image
#   --json                    print the raw API response
#
# Notes:
#   At least one flag is required; with none, the command exits with a usage
#   error rather than sending an empty PATCH.
#   Only the flags you pass are sent, so every unmentioned field keeps its
#   value. --env is the trap: the pairs you give replace the template's whole
#   env map rather than merging into it.
#   --serverless is a bare flag, so update can promote a pod template to a
#   serverless one but cannot demote it again.
#   --volume-gb is ignored with a warning alongside --serverless, exactly as on
#   create.
#   --category is sent only when given: the NVIDIA default is create-side.
#   Pods and endpoints already built from the template are untouched — they
#   copied its container config at create time and never re-read it.
#
# Examples:
#   rp template update tmpl_abc123 --public true
#   rp template update tmpl_abc123 --image myrepo/infer:2 --registry reg_xyz
#
# API: PATCH /v2/templates/{id}

# doc: search
# Find your templates whose name contains a substring.
#
# Usage: rp template search <name-substring> [--json]
#
# Arguments:
#   <name-substring>  text to look for; matching is case-insensitive
#
# Options:
#   --json            print the matching array instead of the table
#
# Notes:
#   The match is client-side: every template is fetched and then filtered on
#   name, because v2 has no search parameter on GET /v2/templates.
#   The columns are the same as `rp template list` — id, name, image and
#   serverless.
#   A template with no name never matches, and a query that matches nothing
#   prints the header row alone.
#   This verb does not page: --limit and --cursor belong to
#   `rp template list`. Narrow the substring instead.
#
# Examples:
#   rp template search pytorch
#   rp template search infer --json
#
# API: GET /v2/templates

# doc: delete
# Delete a template permanently.
#
# Usage: rp template delete <id>
#
# Arguments:
#   <id>  template id — from `rp template list`
#
# Notes:
#   Deletion is irreversible and there is no confirmation prompt.
#   Nothing built from the template goes with it: `rp pod create --template`
#   and the serverless create paths copy the container config at create time,
#   so running pods and endpoints keep their own copy.
#
# API: DELETE /v2/templates/{id}

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
