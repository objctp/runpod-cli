#!/usr/bin/env bash
# Resource descriptor + shared verbs. A resource is a Runpod noun exposed as
# `rp <resource>`: the descriptor maps it to its REST path, list-unwrap key,
# and human label; rp::resource_list/get/delete and rp::resource_id consume it.
# Bespoke verbs (sync, run, start…) stay in commands/<resource>.sh.
# Locals are res_-prefixed: these functions call back into rp::http, which
# tests override with doubles that read their own outer variables — an
# unprefixed `local body` would shadow them (same convention as _mktemp's
# mktemp_out).
[[ -n "${_RP_RESOURCE:-}" ]] && return 0
_RP_RESOURCE=1

# Set RP_RES_PATH / RP_RES_KEY / RP_RES_LABEL for $1, or rp::usage on an
# unknown resource. Internal seam — only this module's verbs read the globals.
_resource_meta() {
  case "$1" in
  pod)
    RP_RES_PATH=/pods
    RP_RES_KEY=pods
    RP_RES_LABEL=pod
    ;;
  volume)
    RP_RES_PATH=/network-volumes
    RP_RES_KEY=networkVolumes
    RP_RES_LABEL=volume
    ;;
  endpoint)
    RP_RES_PATH=/serverless
    RP_RES_KEY=endpoints
    RP_RES_LABEL=endpoint
    ;;
  template)
    RP_RES_PATH=/templates
    RP_RES_KEY=templates
    RP_RES_LABEL=template
    ;;
  registry)
    RP_RES_PATH=/registries
    RP_RES_KEY=registries
    RP_RES_LABEL="registry auth"
    ;;
  *) rp::usage "unknown resource: '$1'" ;;
  esac
}

# List a resource: GET, unwrap, then --json or a table of the given columns.
# $1 resource; remaining args are the table column names.
rp::resource_list() {
  local res_resource="$1"
  shift
  _resource_meta "$res_resource"
  local res_body res_arr
  res_body="$(rp::http GET "$RP_RES_PATH")"
  res_arr="$(rp::unwrap "$RP_RES_KEY" "$res_body")"
  rp::emit_json_or "$res_arr" rp::table "$res_arr" "$@"
}

# Get one record by the positional id: --json raw or pretty-printed JSON.
rp::resource_get() {
  local res_resource="$1" res_id res_body
  _resource_meta "$res_resource"
  rp::require_pos res_id "usage: rp $res_resource get <id>"
  res_body="$(rp::http GET "$RP_RES_PATH/$res_id")"
  rp::emit_json_or "$res_body" rp::json_pretty "$res_body"
}

rp::resource_delete() {
  local res_resource="$1" res_id
  _resource_meta "$res_resource"
  rp::require_pos res_id "usage: rp $res_resource delete <id>"
  rp::http DELETE "$RP_RES_PATH/$res_id" >/dev/null
  rp::ok "deleted $RP_RES_LABEL $res_id"
}

# Create a record: POST the prepared body, extract the new id, confirm on
# stderr, print the id on stdout.
# Arguments:
#   $1 - resource: resource name (pod, volume, endpoint, ...)
#   $2 - name: optional; non-empty makes the create idempotent by name
#   $3 - body: JSON request body
#   $4 - detail: optional text appended to the success message
# Returns:
#   0 - created (or existing id printed when idempotent by name)
#   1 - create failed (dies)
# With a non-empty $2 and no --force, an existing record's id is printed instead
# of POSTing; an empty $2 always POSTs (pod, registry).
rp::resource_create() {
  local res_resource="$1" res_name="$2" res_body="$3" res_detail="${4:-}"
  _resource_meta "$res_resource"
  if [[ -n "$res_name" ]] && ! rp::args_has force; then
    local res_existing
    res_existing="$(rp::resource_id "$res_resource" "$res_name")"
    if [[ -n "$res_existing" ]]; then
      rp::ok "$RP_RES_LABEL '$res_name' exists: $res_existing"
      printf '%s\n' "$res_existing"
      return 0
    fi
  fi
  local res_res res_newid
  res_res="$(rp::http POST "$RP_RES_PATH" "$res_body")"
  rp::extract_id res_newid "$res_res" "$RP_RES_LABEL"
  rp::ok "created $RP_RES_LABEL${res_name:+ '$res_name'}: $res_newid${res_detail:+ ($res_detail)}"
  printf '%s\n' "$res_newid"
}

# Resolve a resource name to its id via list + jq filter; prints the id or
# nothing when no record matches.
rp::resource_id() {
  local res_resource="$1" res_name="$2"
  _resource_meta "$res_resource"
  rp::http GET "$RP_RES_PATH" | rp::unwrap "$RP_RES_KEY" |
    jq -r --arg n "$res_name" '
        (if type == "array" then . else [] end)
        | map(select(.name == $n)) | .[0].id // empty'
}

# Spread a template's container-config fields as a JSON object (the v2 shape
# `rp pod create --template` / `rp endpoint create --template` default from). GETs
# the template and keeps only the non-null fields of the v2 ContainerConfig.
rp::template_spread() {
  rp::http GET "/templates/$1" | jq -c '{image, args, disk, ports, env, registry} | with_entries(select(.value != null))'
}

# Network-volume name → datacenter.
# Arguments:
#   $1 - name: the network-volume name
# Returns:
#   0 - resolved; sets RP_VOLUME_ID and RP_VOLUME_DC in the caller's shell
#   1 - volume not found / no datacenter (dies)
# Invoke in the main shell, not a command substitution, so the exit fires.
rp::volume_dc() {
  local vd_name="$1"
  RP_VOLUME_ID="$(rp::resource_id volume "$vd_name")"
  [[ -n "$RP_VOLUME_ID" ]] || rp::notfound "volume '$vd_name' not found"
  rp::volume_dc_id "$RP_VOLUME_ID"
}

rp::volume_dc_id() {
  local vd_id="$1"
  RP_VOLUME_ID="$vd_id"
  RP_VOLUME_DC="$(rp::http GET "/network-volumes/$vd_id" | jq -r '.dataCenter // empty')"
  [[ -n "$RP_VOLUME_DC" ]] || rp::die "volume '$vd_id' has no datacenter"
}
