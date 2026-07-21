#!/usr/bin/env bash
# RunPod S3-API helpers — region/endpoint derivation and `aws s3 sync`/`ls` wrappers.
[[ -n "${_RP_S3:-}" ]] && return 0
_RP_S3=1

_s3_region() { printf '%s' "${1,,}"; }

_s3_endpoint() { printf 'https://s3api-%s.runpod.io/' "${1,,}"; }

_s3_env() {
  rp::require_s3_creds
  export AWS_ACCESS_KEY_ID="$RUNPOD_S3_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$RUNPOD_S3_SECRET_KEY"
}

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
    --cli-read-timeout 7200
}

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
