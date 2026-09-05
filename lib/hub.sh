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

# Marketplace listings are GraphQL-only (no API v2 path). The selection set is
# identical for search and list; only the ListingsInput differs, so both verbs
# share this query string.
RP_HUB_LISTINGS_QUERY='query($input:ListingsInput!){ listings(input:$input){ id title repoOwner repoName type } }'

_gpu_pools_json() {
  if [[ -z "$_RP_GPU_POOLS" ]]; then
    _RP_GPU_POOLS="$(rp::http GET /catalog/gpus | rp::unwrap gpus | jq -c '
      group_by(.pool) | map({id: .[0].pool, gpuTypeIds: map(.id)})')"
  fi
  printf '%s' "$_RP_GPU_POOLS"
}

# listings(input: ListingsInput!) -> JSON array of {id,title,repoOwner,repoName,type}
rp::hub_search() {
  local query="$1" limit="${2:-$RP_HUB_SEARCH_LIMIT}"
  local vars
  vars="$(jq -c -n --arg s "$query" --argjson l "$limit" '{input:{searchQuery:$s,limit:$l}}')"
  rp::graphql "$RP_HUB_LISTINGS_QUERY" "$vars" | jq -c '.listings'
}

# listings(input: ListingsInput!) without a searchQuery — list the marketplace
# filtered by the ListingsInput args. `type` is NOT a query arg: it is applied
# afterwards as a client-side post-filter. `category`, `orderBy`, `orderDir`,
# `owner`, `limit`, `offset` thread straight into ListingsInput; unset ones are
# omitted so the API applies its own defaults. Returns the `.listings` array.
rp::hub_list() {
  local category="$1" order_by="$2" order_dir="$3" owner="$4" limit="$5" offset="$6" type="$7"
  local q="$RP_HUB_LISTINGS_QUERY"
  local vars
  vars="$(jq -c -n \
    --arg category "$category" \
    --arg orderBy "$order_by" \
    --arg orderDirection "$order_dir" \
    --arg owner "$owner" \
    --arg limit "$limit" \
    --arg offset "$offset" \
    '{
      input: ({} as $in
        | (if $category != "" then $in + {category: $category} else $in end) as $in
        | (if $orderBy != "" then $in + {orderBy: $orderBy} else $in end) as $in
        | (if $orderDirection != "" then $in + {orderDirection: $orderDirection} else $in end) as $in
        | (if $owner != "" then $in + {owner: $owner} else $in end) as $in
        | (if $limit != "" then $in + {limit: ($limit | tonumber)} else $in end) as $in
        | (if $offset != "" then $in + {offset: ($offset | tonumber)} else $in end))
    }')"
  local data
  data="$(rp::graphql "$q" "$vars" | jq -c '.listings')"
  if [[ -n "$type" ]]; then
    data="$(printf '%s' "$data" | jq -c --arg t "$type" 'map(select(.type == $t))')"
  fi
  printf '%s' "$data"
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

# Validate an --exclude-gpu CSV against a pool selection. excludedTypes
# subtracts GPU type ids from the selected `pools` (there is no inclusive
# allowlist), and the API silently accepts exclusions that are unknown or sit
# outside the selection — a typo would just exclude nothing. Each type must
# therefore be a known catalogue member AND belong to one of $2's pools.
# Arguments:
#   $1 - types_csv: comma-separated GPU type ids to exclude
#   $2 - pools_csv: comma-separated pool ids the exclusions apply to
# Returns:
#   0 - every type is known and covered by the selected pools
#   2 - otherwise (rp::usage, naming the offending type and its pools)
# Call DIRECTLY, never inside command substitution: rp::usage's exit must fire
# in the caller's shell.
rp::gpu_excluded_validate() {
  local types_csv="$1" pools_csv="$2"
  [[ -n "$types_csv" ]] || return 0
  local t hit
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    hit="$(_gpu_pools_json | jq -r --arg t "$t" --argjson pools "$(rp::csv_to_jsonarray "$pools_csv")" '
      . as $p
      | [$p[] | select((.gpuTypeIds // []) | index($t)) | .id] as $own
      | if ($own | length) == 0 then "unknown|"
        elif ([$own[] | select(. as $o | $pools | index($o))] | length) == 0 then "other|" + ($own | join(", "))
        else "ok" end')"
    case "${hit%%|*}" in
    unknown) rp::usage "--exclude-gpu '$t' is not a known GPU type (see: rp stock gpu)" ;;
    other) rp::usage "--exclude-gpu '$t' is not in the selected pools ($pools_csv); it belongs to: ${hit#*|}" ;;
    esac
  done < <(rp::split_csv "$types_csv")
}
