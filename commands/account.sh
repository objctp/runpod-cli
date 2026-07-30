#!/usr/bin/env bash
# `rp account` has a single useful action (show balance + spend), so the default
# verb is `info`: both `rp account` and `rp account info` print the same thing.

_account_info_human() {
  printf '%s' "$1" | jq -r '
    .myself |
    "USER            \(.id // "")",
    "BALANCE         $\((.clientBalance // 0))",
    "SPEND LIMIT     $\((.spendLimit // 0))",
    "SPEND / HOUR    $\((.currentSpendPerHr // 0))"'
}

_account_info() {
  local data
  data="$(rp::graphql 'query { myself { id clientBalance spendLimit currentSpendPerHr } }')"
  rp::emit_json_or "$data" _account_info_human "$data"
}

rp::cmd_account() {
  local verb="${1:-info}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  -h | --help | help)
    echo "Usage: rp account [info]   (balance + spend via GraphQL — no API v2 endpoint yet)"
    ;;
  info) _account_info ;;
  *) rp::usage "unknown account verb: '$verb'" ;;
  esac
}
