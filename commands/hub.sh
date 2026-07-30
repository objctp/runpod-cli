#!/usr/bin/env bash
# `rp hub` — Hub marketplace search/get (GraphQL).

_hub_search_cmd() {
  local q
  rp::require_pos q "usage: rp hub search <query>"
  local data
  data="$(rp::hub_search "$q" 20)"
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

rp::cmd_hub() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  search) _hub_search_cmd ;;
  get) _hub_get_cmd ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp hub <verb>   (via GraphQL — Hub has no API v2 endpoint yet)
  search <query>          Hub marketplace search; id starts the listing id
  get <listing-id>        listing details: release, build image, config
EOF
    ;;
  *) rp::usage "unknown hub verb: '$verb'" ;;
  esac
}
