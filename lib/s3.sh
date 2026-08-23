#!/usr/bin/env bash
# Runpod S3-API helpers — region/endpoint derivation and `aws s3 sync`/`ls` wrappers.
[[ -n "${_RP_S3:-}" ]] && return 0
_RP_S3=1

_s3_region() { printf '%s' "${1,,}"; }

_s3_endpoint() { printf 'https://s3api-%s.runpod.io/' "${1,,}"; }

_s3_env() {
  rp::require_s3_creds
  export AWS_ACCESS_KEY_ID="$RUNPOD_S3_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$RUNPOD_S3_SECRET_KEY"
}

# Sync a local dir to an S3 bucket/prefix.
# Arguments:
#   $1 - src: local source directory
#   $2 - bucket: destination bucket name
#   $3 - dc: datacentre id (sets region + endpoint)
#   $4 - prefix: optional key prefix
# Returns:
#   0 - sync succeeded
#   1 - aws failed (dies)
# Exports AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY via _s3_env and uses a 7200s
# CLI read timeout for large volume transfers.
rp::s3_sync() {
  local src="$1"
  local bucket="$2"
  local dc="$3"
  local prefix="${4:-}"
  rp::require_cmd aws
  _s3_env
  local dst="s3://$bucket"
  [[ -n "$prefix" ]] && dst="$dst/$prefix"
  aws s3 sync "$src" "$dst/" \
    --region "$(_s3_region "$dc")" \
    --endpoint-url "$(_s3_endpoint "$dc")" \
    --cli-read-timeout "$RP_TIMEOUT_S3_READ"
}

# List an S3 bucket/prefix.
# Arguments:
#   $1 - bucket: bucket name
#   $2 - dc: datacentre id (sets region + endpoint)
#   $3 - prefix: optional key prefix
# Returns:
#   0 - listing succeeded
#   1 - aws failed (dies)
# Exports AWS creds via _s3_env.
rp::s3_ls() {
  local bucket="$1"
  local dc="$2"
  local prefix="${3:-}"
  rp::require_cmd aws
  _s3_env
  local target="s3://$bucket"
  [[ -n "$prefix" ]] && target="$target/$prefix"
  aws s3 ls "$target/" \
    --region "$(_s3_region "$dc")" \
    --endpoint-url "$(_s3_endpoint "$dc")"
}
