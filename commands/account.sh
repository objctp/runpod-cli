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
#   Backed by the GraphQL `myself` query — there is no API v2 equivalent in the
#   current v2 spec (confirmed against /v2/openapi.json: no user/account read
#   endpoint exists; only /v2/account/ssh-keys). Runs until the early-2027
#   GraphQL retirement; revisit if Runpod ships a v2 account endpoint.
#
# API: GraphQL `myself { id email clientBalance spendLimit currentSpendPerHr
#      notifyPodsStale notifyPodsGeneral notifyLowBalance }` (NO-V2-EQUIVALENT)

rp::cmd_account() {
  local verb="${1:-info}"
  shift || true
  _RP_SUNSET=""
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  -h | --help | help)
    echo "Usage: rp account [info]   (balance + spend via GraphQL — no API v2 endpoint yet)"
    ;;
  info) _account_info ;;
  *) rp::usage "unknown account verb: '$verb'" ;;
  esac
  # GraphQL bridge: stays until Runpod ships a v2 account endpoint or retires
  # GraphQL (early 2027). Warn every invocation (help excluded) and append the
  # Sunset header countdown when the server starts sending it.
  [[ "$verb" == "help" ]] && return 0
  rp::warn "rp account is GraphQL-backed; Runpod retires GraphQL in early 2027${_RP_SUNSET:+ (Sunset: $_RP_SUNSET)}. It will move to a v2 endpoint when one is available."
}
