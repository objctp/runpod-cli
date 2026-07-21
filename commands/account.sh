#!/usr/bin/env bash
# `rp account` has a single useful action (show balance + spend), so the default
# verb is `info`: both `rp account` and `rp account info` print the same thing.

_account_info() {
  local data
  data="$(rp::graphql 'query { myself { id clientBalance spendLimit currentSpendPerHr } }')"
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  printf '%s' "$data" | jq -r '
    .myself |
    "USER            \(.id // "")",
    "BALANCE         $\((.clientBalance // 0))",
    "SPEND LIMIT     $\((.spendLimit // 0))",
    "SPEND / HOUR    $\((.currentSpendPerHr // 0))"'
}

rp::cmd_account() {
  local verb="${1:-info}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  -h | --help | help)
    echo "Usage: rp account [info]   (balance + spend via GraphQL)"
    ;;
  info) _account_info ;;
  *) rp::usage "unknown account verb: '$verb'" ;;
  esac
}
