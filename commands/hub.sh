#!/usr/bin/env bash
# `rp hub` — Hub marketplace search/get (GraphQL).

_hub_search_cmd() {
  local q
  q="$(rp::args_pos)"
  [[ -n "$q" ]] || rp::usage "usage: rp hub search <query>"
  local data
  data="$(rp::hub_search "$q" 20)"
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  rp::table "$data" id title repoOwner type
}

_hub_get_cmd() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp hub get <listing-id>"
  local data
  data="$(rp::hub_get "$id")"
  [[ "$data" != "null" ]] || rp::notfound "hub listing '$id' not found"
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  printf '%s' "$data" | jq -r '
    "# \(.title) — \(.repoOwner)/\(.repoName) [\(.type)]",
    "release:  \(.listedRelease.name // "") (\(.listedRelease.tagName // ""))",
    "image:    \(.listedRelease.build.imageName // "")",
    "config:   \(.listedRelease.config // "")"'
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
Usage: rp hub <verb>
  search <query>          Hub marketplace search (GraphQL); id starts the listing id
  get <listing-id>        listing details: release, build image, config
EOF
    ;;
  *) rp::usage "unknown hub verb: '$verb'" ;;
  esac
}
