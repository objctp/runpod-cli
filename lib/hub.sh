#!/usr/bin/env bash
[[ -n "${_RP_HUB:-}" ]] && return 0
_RP_HUB=1

# Hub marketplace + GPU-pool helpers (all GraphQL, same api.runpod.io endpoint).
# Field names mirror runpodctl's hub.go / endpoints.go (introspection is disabled
# on the live endpoint, so runpodctl source is the source of truth).

# serverlessGpuPools -> JSON [{id, gpuTypeIds}], cached for the process lifetime.
# v2 source: GET /v2/catalog/gpus, which carries the `pool` id per GPU type. We
# regroup by pool so the downstream type-name -> pool mapping is unchanged.
_RP_GPU_POOLS=''

_gpu_pools_json() {
  if [[ -z "$_RP_GPU_POOLS" ]]; then
    _RP_GPU_POOLS="$(rp::http GET /catalog/gpus | rp::unwrap gpus | jq -c '
      group_by(.pool) | map({id: .[0].pool, gpuTypeIds: map(.id)})')"
  fi
  printf '%s' "$_RP_GPU_POOLS"
}

# listings(input: ListingsInput!) -> JSON array of {id,title,repoOwner,repoName,type}
rp::hub_search() {
  local query="$1" limit="${2:-20}"
  local q='query($input:ListingsInput!){ listings(input:$input){ id title repoOwner repoName type } }'
  local vars
  vars="$(jq -c -n --arg s "$query" --argjson l "$limit" '{input:{searchQuery:$s,limit:$l}}')"
  rp::graphql "$q" "$vars" | jq -c '.listings'
}

# listing(id: String!) -> JSON {id,title,repoOwner,repoName,type,listedRelease{name,tagName,build{imageName},config}}
rp::hub_get() {
  local id="$1"
  local q='query($id:String!){ listing(id:$id){ id title repoOwner repoName type listedRelease { name tagName build { imageName } config } } }'
  local vars
  vars="$(jq -c -n --arg id "$id" '{id:$id}')"
  rp::graphql "$q" "$vars" | jq -c '.listing'
}

# Translate a CSV of GPU type names -> CSV of pool ids (first pool covering each).
# saveEndpoint's gpuIds wants pool ids (e.g. AMPERE_80), not type display names.
rp::gpu_type_to_pool_csv() {
  local types="$1"
  [[ -n "$types" ]] || return 0
  local want
  want="$(rp::csv_to_jsonarray "$types")"
  _gpu_pools_json | jq -r --argjson want "$want" '
    . as $pools
    | [$want[] | . as $t | ($pools | map(select((.gpuTypeIds // []) | index($t))) | .[0].id // empty)]
    | map(select(. != null)) | join(",")'
}
