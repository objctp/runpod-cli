#!/usr/bin/env bash
#
# Show your account balance and spend.
#
# The only verb is `info`, also the default: `rp account` and `rp account info`
# print the same balance, spend limit and per-hour spend.
#
# Usage: rp account <verb> [flags]
#

_account_info_human() {
  printf '%s' "$1" | jq -r '
    .myself |
    "USER            \(.id // "")",
    "EMAIL           \(.email // "")",
    "BALANCE         $\((.clientBalance // 0))",
    "SPEND LIMIT     $\((.spendLimit // 0))",
    "SPEND / HOUR    $\((.currentSpendPerHr // 0))",
    "NOTIFY STALE    \(.notifyPodsStale // false)",
    "NOTIFY GENERAL  \(.notifyPodsGeneral // false)",
    "NOTIFY LOW BAL  \(.notifyLowBalance // false)"'
}

_account_info() {
  local data
  data="$(rp::graphql 'query { myself { id email clientBalance spendLimit currentSpendPerHr notifyPodsStale notifyPodsGeneral notifyLowBalance } }')"
  rp::emit_json_or "$data" _account_info_human "$data"
}

###
### :::: documentation (rp doc account) :::: ######################################
###

# doc: info
# Show your account balance and spend.
#
# Usage: rp account [info]
#
# Options:
#   --json  print the raw GraphQL response
#
# Notes:
#   Backed by the GraphQL `myself` query — there is no API v2 equivalent
#   (see docs/API_ALIGNMENT_REPORT_V2.md, NO-V2-EQUIVALENT list, line ~753).
#
# API: GraphQL `myself { id email clientBalance spendLimit currentSpendPerHr
#      notifyPodsStale notifyPodsGeneral notifyLowBalance }` (NO-V2-EQUIVALENT)

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
