#!/usr/bin/env bash
#
# Container-registry credentials and ECR access delegations.
#
# A registry auth entry lets a pod or endpoint pull a private image without
# embedding a password in the container. An ECR delegation links an AWS account
# to Runpod so images can be pulled from a private Elastic Container Registry
# without a stored credential at all. Both surfaces use REST API v2.
#
# Usage: rp registry <verb> [flags]
#

# Unwrapped `delegations` array; --json passes it through.
_registry_delegations_list() {
  local data
  data="$(rp::http GET /registries/delegations | rp::unwrap delegations)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, NAME:(.name//""), REPOSITORY:.repository, TAG:.tag, REGION:.awsRegion, CREATED:(.createdAt//"")})' \
    ID NAME REPOSITORY TAG REGION CREATED
}

# POST /v2/registries/delegations; `name` is optional and omitted when empty.
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

# DELETE a delegation (204 on success).
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
  # The password is written to a 0600 temp file and merged via rp::obj_set_secret
  # so it never reaches jq's argv (visible in `ps`); only name/username — which
  # are not secrets — travel on the command line.
  local body secret_tmp
  _mktemp secret_tmp
  printf '%s' "$password" >"$secret_tmp"
  body="$(rp::json_obj name "$(rp::json_str "$name")" username "$(rp::json_str "$username")")"
  rp::obj_set_secret body password "$secret_tmp"
  rp::resource_create registry "" "$body"
}

###
### :::: documentation (rp doc registry) :::: #####################################
###

# doc: delegations
# Manage ECR access delegations between an AWS account and Runpod.
#
# Usage: rp registry delegations <verb> [flags]
#
# Notes:
#   A delegation links an ECR repository so private images can be pulled without
#   a stored registry credential. Sub-verbs: list, create, revoke.
#
# API: GET /v2/registries/delegations

# doc: delegations list
# List your ECR access delegations.
#
# Usage: rp registry delegations list [--json]
#
# Options:
#   --json           print the raw API response
#
# Notes:
#   The table shows each delegation's id, name, repository, tag, AWS region and
#   creation time.
#
# API: GET /v2/registries/delegations

# doc: delegations create
# Link an ECR repository for credential-free private-image pulls.
#
# Usage: rp registry delegations create --resource <ecr-arn> [--name <n>]
#
# Options:
#   --resource <ecr-arn>         the ECR repository ARN to delegate (required)
#   --name <n>                   label for the delegation (optional; omitted
#                                from the body when not given)
#   --json                       print the raw API response
#
# Notes:
#   On success the new delegation id is printed; the name is optional and, when
#   absent, is not sent in the request body.
#
# API: POST /v2/registries/delegations

# doc: delegations revoke
# Remove an ECR access delegation.
#
# Usage: rp registry delegations revoke <id>
#
# Arguments:
#   <id>             delegation id — from `rp registry delegations list`
#
# Notes:
#   Removal is irreversible; images from that repository will then need a stored
#   credential to be pulled again.
#
# API: DELETE /v2/registries/delegations/{id}

# doc: list
# List your registry credentials: id and name.
#
# Usage: rp registry list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N        return at most N credentials
#   --cursor <c>     offset to resume from; pairs with --limit
#   --jq <filter>    jq filter applied to the array
#   --json           print the raw API response
#
# API: GET /v2/registries

# doc: get
# Show one registry credential's full record.
#
# Usage: rp registry get <id> [--jq <filter>] [--json]
#
# Arguments:
#   <id>             credential id — from `rp registry list`
#
# Options:
#   --jq <filter>    jq filter applied to the record
#   --json           print the raw API response instead of pretty JSON
#
# API: GET /v2/registries/{id}

# doc: create
# Store a container-registry credential for pulling private images.
#
# Usage: rp registry create --name <n> --username <u> [--password <p>]
#
# Options:
#   --name <n>                credential name (required)
#   --username <u>            registry username (required)
#   --password <p>            registry password; if omitted, prompts interactively
#
# Notes:
#   --password is visible in process listings (`ps`) and shell history; prefer
#   the interactive prompt by omitting it.
#   The credential is not idempotent by name, so re-running create adds a second
#   entry rather than updating the first.
#
# API: POST /v2/registries

# doc: delete
# Delete a registry credential.
#
# Usage: rp registry delete <id>
#
# Arguments:
#   <id>             credential id — from `rp registry list`
#
# Notes:
#   Deletion is irreversible; pods or endpoints still referencing the credential
#   will fail to pull.
#
# API: DELETE /v2/registries/{id}

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
  list                                   ECR access delegations (AWS account ↔ Runpod)
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
