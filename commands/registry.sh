#!/usr/bin/env bash
#
# `rp registry` — container-registry auth CRUD (REST API v2).
# Usage: rp registry <verb> [flags]
#

# rp registry delegations list — ECR access delegations (AWS account ↔ RunPod).
# GET /v2/registries/delegations (listDelegations). --json emits the unwrapped
# `delegations` array (the envelope carries no extra metadata).
_registry_delegations_list() {
  local data
  data="$(rp::http GET /registries/delegations | rp::unwrap delegations)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, NAME:(.name//""), REPOSITORY:.repository, TAG:.tag, REGION:.awsRegion, CREATED:(.createdAt//"")})' \
    ID NAME REPOSITORY TAG REGION CREATED
}

# rp registry delegations create --resource <ecr-arn> [--name <n>] — link an ECR
# repo so private images can be pulled without a stored credential.
# POST /v2/registries/delegations (createDelegation); 201 returns the full
# EcrDelegation, whose top-level .id rp::extract_id reads. `name` is optional and
# omitted from the body when not given (the silent-empty guard below, because
# rp::json_str "" would otherwise emit "name":"" — see Notes).
_registry_delegations_create() {
  local resource
  resource="$(rp::args_get resource)"
  [[ -n "$resource" ]] || rp::usage "usage: rp registry delegations create --resource <ecr-arn> [--name <n>]"
  local obj='{}'
  rp::obj_set obj resource "$(rp::json_str "$resource")"
  local name
  name="$(rp::args_get name)"
  [[ -z "$name" ]] || rp::obj_set obj name "$(rp::json_str "$name")"
  local res newid
  res="$(rp::http POST /registries/delegations "$obj")"
  rp::extract_id newid "$res" "ECR delegation"
  rp::ok "created ECR delegation${name:+ '$name'}: $newid"
  printf '%s\n' "$newid"
}

# rp registry delegations revoke <id> — remove a delegation. DELETE, 204 on success.
_registry_delegations_revoke() {
  local id
  rp::require_pos id "usage: rp registry delegations revoke <id>"
  rp::http DELETE "/registries/delegations/$id" >/dev/null
  rp::ok "revoked ECR delegation $id"
}

_registry_create() {
  local name username password
  name="$(rp::args_get name)"
  username="$(rp::args_get username)"
  password="$(rp::args_get password)"
  [[ -n "$name" && -n "$username" ]] || rp::usage "usage: rp registry create --name <n> --username <u> [--password <p> (prefer interactive prompt)]"
  if [[ -z "$password" ]]; then
    IFS= read -rs -p "Password: " password </dev/tty || true
    echo >&2
    [[ -n "$password" ]] || rp::usage "no password entered"
  else
    rp::warn "note: --password is visible in process listings and shell history; prefer the interactive prompt"
  fi
  local body
  body="$(rp::json_obj name "$(rp::json_str "$name")" username "$(rp::json_str "$username")" password "$(rp::json_str "$password")")"
  rp::resource_create registry "" "$body"
}

rp::cmd_registry() {
  local verb="${1:-help}"
  shift || true
  if [[ "$verb" == "delegations" ]]; then
    local sub="${1:-help}"
    shift || true
    rp::args_parse "$@"
    rp::args_has help && sub=help
    case "$sub" in
    list) _registry_delegations_list ;;
    create) _registry_delegations_create ;;
    revoke) _registry_delegations_revoke ;;
    -h | --help | help)
      cat <<'EOF'
Usage: rp registry delegations <verb> [flags]
  list                                   ECR access delegations (AWS account ↔ RunPod)
  create --resource <ecr-arn> [--name <n>]   link an ECR repo for private-image pulls
  revoke <id>                            remove a delegation
EOF
      ;;
    *) rp::usage "unknown delegations verb: '$sub' (see: rp registry delegations --help)" ;;
    esac
    return
  fi
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list registry id name ;;
  get) rp::resource_get registry ;;
  create) _registry_create ;;
  delete) rp::resource_delete registry ;;
  -h | --help | help)
    echo "Usage: rp registry <create|list|get|delete> | delegations <list|create|revoke>"
    ;;
  *) rp::usage "unknown registry verb: '$verb'" ;;
  esac
}
