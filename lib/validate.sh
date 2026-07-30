#!/usr/bin/env bash
[[ -n "${_RP_VALIDATE:-}" ]] && return 0
_RP_VALIDATE=1

# Offline fallback snapshot of S3-API-enabled datacentres — verified identical to
# the live `dataCenters { s3apiEnabled }` query on 2026-07-20. The live query is
# the source of truth (see _s3_dcs); this array only backs the guard when the
# API is unreachable, so `rp volume create` / `sync` still work offline. `rp
# stock dc` always renders the live s3apiEnabled value, never this snapshot.
RP_S3_DCS_FALLBACK=(
  EU-CZ-1
  EU-RO-1
  EUR-IS-1
  EUR-NO-1
  US-CA-2
  US-GA-2
  US-IL-1
  US-KS-2
  US-MD-1
  US-MO-1
  US-MO-2
  US-NC-1
  US-NC-2
  US-NE-1
  US-WA-1
)

# Resolved S3-API DC set, cached for the process lifetime.
_RP_S3_DCS=()

# Populate _RP_S3_DCS once: live `dataCenters { s3apiEnabled }` query first,
# falling back to the static snapshot if the query fails or returns nothing.
_s3_dcs_ensure() {
  ((${#_RP_S3_DCS[@]} > 0)) && return 0
  local live
  if live="$(_s3_dcs_live 2>/dev/null)" && [[ -n "$live" ]]; then
    mapfile -t _RP_S3_DCS <<<"$live"
  else
    _RP_S3_DCS=("${RP_S3_DCS_FALLBACK[@]}")
  fi
}

# Print the S3-API-enabled datacentre ids (one per line), live where reachable.
_s3_dcs() {
  _s3_dcs_ensure
  printf '%s\n' "${_RP_S3_DCS[@]}"
}

# Live S3-enabled DC ids (one per line). Returns non-zero / empty on any failure
# (transport, HTTP, or GraphQL errors) so _s3_dcs can fall back. Soft by
# design — delegates to rp::graphql_soft, which owns the curl/transport seam and
# never dies (unlike rp::graphql).
_s3_dcs_live() {
  local data
  data="$(rp::graphql_soft 'query { dataCenters { id s3apiEnabled } }')" || return 1
  [[ -n "$data" ]] || return 1
  printf '%s' "$data" |
    jq -re '.dataCenters[]? | select(.s3apiEnabled == true) | .id' 2>/dev/null
}

rp::is_s3_dc() {
  _s3_dcs_ensure
  local target="${1^^}" x
  for x in "${_RP_S3_DCS[@]}"; do
    [[ "$x" == "$target" ]] && return 0
  done
  return 1
}

rp::warn_unless_s3_dc() {
  rp::is_s3_dc "$1" || rp::warn "note: datacenter '$1' is not S3-API supported — 'rp volume sync' won't work (see: rp stock dc)"
}
