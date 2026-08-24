#!/usr/bin/env bash
#
# Search the Hub marketplace and read a listing.
#
# The Hub is the catalogue of ready-made repositories that deploy as serverless
# endpoints. Both verbs are read-only and GraphQL-backed — API v2 has no
# marketplace path. The write half already moved: pass a listing id to
# `rp serverless create --hub-id` and the deploy goes over v2.
#
# Usage: rp hub <verb> [flags]
#

_hub_search_cmd() {
  local q
  rp::require_pos q "usage: rp hub search <query>"
  local data
  data="$(rp::hub_search "$q" "$RP_HUB_SEARCH_LIMIT")"
  rp::emit_json_or "$data" rp::table "$data" id title repoOwner type
}

_hub_get_human() {
  printf '%s' "$1" | jq -r '
    "# \(.title) — \(.repoOwner)/\(.repoName) [\(.type)]",
    "release:  \(.listedRelease.name // "") (\(.listedRelease.tagName // ""))",
    "image:    \(.listedRelease.build.imageName // "")",
    "config:   \(.listedRelease.config // "")"'
}

_hub_get_cmd() {
  local id
  rp::require_pos id "usage: rp hub get <listing-id>"
  local data
  data="$(rp::hub_get "$id")"
  [[ "$data" != "null" ]] || rp::notfound "hub listing '$id' not found"
  rp::emit_json_or "$data" _hub_get_human "$data"
}

_hub_list_cmd() {
  local category order_by order_dir owner limit offset type
  category="$(rp::args_get category)"
  order_by="$(rp::args_get order-by)"
  order_dir="$(rp::args_get order-dir)"
  owner="$(rp::args_get owner)"
  limit="$(rp::args_get_uint limit "")"
  offset="$(rp::args_get_uint offset "")"
  # API types are POD/SERVERLESS; accept the user's casing so a lowercase flag
  # value still matches the response rather than silently returning nothing.
  type="$(rp::args_get type | tr '[:lower:]' '[:upper:]')"
  local data
  data="$(rp::hub_list "$category" "$order_by" "$order_dir" "$owner" "$limit" "$offset" "$type")"
  rp::emit_json_or "$data" rp::table "$data" id title repoOwner type
}

###
### :::: documentation (rp doc hub) :::: ######################################
###

# doc: search
# Search Hub listings by keyword.
#
# Usage: rp hub search <query> [--json]
#
# Arguments:
#   <query>  search text; quote anything with spaces
#
# Options:
#   --json   print the raw listings array
#
# Notes:
#   The table shows the listing id, title, owner and type. That id is what
#   `rp hub get` and `rp serverless create --hub-id` take.
#   Results are capped at 20 and the cap is not exposed as a flag, so narrow
#   the query rather than paging.
#   The text goes to the Hub as its own searchQuery input, so the ordering is
#   the marketplace's ranking, not a substring match the CLI performs.
#   A query matching nothing prints just the header row.
#
# Examples:
# # Search the Hub for Stable Diffusion listings
# $ rp hub search "stable diffusion"
# # Search the Hub for Whisper listings
# $ rp hub search whisper
#
# API: GraphQL listings(input: { searchQuery, limit })  (NO-V2-EQUIVALENT)

# doc: get
# Show one Hub listing: release, image and config.
#
# Usage: rp hub get <listing-id> [--json]
#
# Arguments:
#   <listing-id>  listing id — from `rp hub search`
#
# Options:
#   --json        print the raw listing object
#
# Notes:
#   The human view prints the title and repository, the listed release name
#   and tag, the built image reference, and the listing's config blob.
#   config is the deployment recipe `rp serverless create --hub-id` reads, so
#   this verb is how you see what that command will build before running it.
#   An unknown id is a not-found error rather than an empty record: the query
#   answers null and the CLI exits on it.
#
# API: GraphQL listing(id)  (NO-V2-EQUIVALENT)

# doc: list
# Browse all Hub listings, filtered and ordered.
#
# Usage: rp hub list [--category <c>] [--order-by <field>] [--order-dir ASC|DESC]
#                     [--owner <owner>] [--limit <n>] [--offset <n>] [--type <t>] [--json]
#
# Options:
#   --category <c>     filter by category
#   --order-by <field> sort field (e.g. createdAt)
#   --order-dir <dir>  ASC or DESC
#   --owner <owner>    restrict to a repository owner
#   --limit <n>        max rows to return
#   --offset <n>       rows to skip (paging)
#   --type POD|SERVERLESS  the API has no type arg, so this filters the result
#                      set client-side after the query (case-insensitive)
#   --json             print the raw listings array
#
# Notes:
#   The table shows the listing id, title, owner and type — the same shape as
#   `rp hub search`. That id is what `rp hub get` and `rp serverless create
#   --hub-id` take.
#   Filters map to the GraphQL ListingsInput args; `--type` is the only flag
#   applied after the response returns, because the API offers no type filter.
#
# API: GraphQL listings(input: {category,orderBy,orderDirection,owner,limit,offset})  (NO-V2-EQUIVALENT)

rp::cmd_hub() {
  local verb="${1:-help}"
  shift || true
  _RP_SUNSET=""
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  search) _hub_search_cmd ;;
  list) _hub_list_cmd ;;
  get) _hub_get_cmd ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp hub <verb>   (via GraphQL — Hub has no API v2 endpoint yet)
  search <query>          Hub marketplace search; id starts the listing id
  list                    browse all listings, filtered and ordered
  get <listing-id>        listing details: release, build image, config
EOF
    ;;
  *) rp::usage "unknown hub verb: '$verb'" ;;
  esac
  # GraphQL bridge: the Hub has NO v2 endpoint, so this is the highest-risk
  # surface — it stops working outright when GraphQL is retired (early 2027)
  # unless Runpod ships a v2 Hub path. Warn every invocation (help excluded) and
  # append the Sunset header countdown when the server starts sending it.
  [[ "$verb" == "help" ]] && return 0
  rp::warn "rp hub is GraphQL-backed and has no v2 endpoint yet; it will stop working when the GraphQL API is retired${_RP_SUNSET:+ (Sunset: $_RP_SUNSET)}."
}
