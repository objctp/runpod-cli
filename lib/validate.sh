#!/usr/bin/env bash
[[ -n "${_RP_VALIDATE:-}" ]] && return 0
_RP_VALIDATE=1

# Datacentre + S3-API + network-volume-tier validation helpers. Guards
# `volume create`/`sync` on S3-enabled datacentres, checks the high-performance
# volume tier at create, and resolves datacentre stock.

# Offline fallback snapshot of S3-API-enabled datacentres — verified identical to
# the live `dataCenters { s3apiEnabled }` query on 2026-07-20. The live GraphQL
# query is the source of truth (see _s3_dcs_live); this array only backs the
# guard when the API is unreachable, so `rp volume create` / `sync` still work
# offline. `rp stock dc` also falls back to it when GraphQL is down. Keep it
# current with Runpod's S3-API datacentre list.
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

# Populate _RP_S3_DCS once: live GraphQL `dataCenters { s3apiEnabled }` first,
# falling back to the static snapshot only if the query fails or returns
# nothing. GraphQL is still the source of truth for the S3 signal until Runpod
# retires it (early 2027) or ships an `s3apiEnabled` field on the v2 catalog;
# the v2 /catalog/datacenters carries only the `networkVolumeTypes` tier enum
# (STANDARD|HIGH_PERFORMANCE) and no S3 flag, so v2 alone would freeze the set
# on RP_S3_DCS_FALLBACK and never pick up new S3 datacentres.
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
# (transport, HTTP, or GraphQL errors) so _s3_dcs can fall back. Soft by design
# — delegates to rp::graphql_soft, which owns the curl/transport seam and never
# dies (unlike rp::graphql). GraphQL stays the live source for the S3 signal
# until Runpod retires it or exposes `s3apiEnabled` on the v2 catalog (v2 ships
# only the `networkVolumeTypes` tier enum — see _hp_dc_tiers).
_s3_dcs_live() {
  local data
  data="$(rp::graphql_soft 'query { dataCenters { id s3apiEnabled } }')" || return 1
  [[ -n "$data" ]] || return 1
  printf '%s' "$data" |
    jq -re '.dataCenters[]? | select(.s3apiEnabled == true) | .id' 2>/dev/null
}

# Return 0 if $1 names an S3-API-enabled datacentre, else 1.
# Arguments:
#   $1 - dc: datacentre id (case-insensitive)
# Returns:
#   0 - $1 is an S3-enabled datacentre
#   1 - not S3-enabled
# The first call triggers a network request (via _s3_dcs_ensure) to populate the
# cached datacentre list; subsequent calls are local.
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

# Fetch one datacentre's network-volume tiers from the v2 catalog (single-DC
# GET /catalog/datacenters/{id} — the documented carrier of the
# `networkVolumeTypes` enum array, STANDARD|HIGH_PERFORMANCE; the GraphQL
# dataCenters query has no tier field). Prints the tiers as a compact
# upper-cased JSON array — `[]` is a valid answer meaning "no tiers listed".
# Returns non-zero (prints nothing) on transport failure, HTTP >= 400, or an
# unparseable body, so callers can treat capability as UNKNOWN rather than
# false. Soft by design — rp::http_soft owns the curl seam and never dies
# (unlike rp::http, whose die-on-4xx would kill `volume create` on an unknown
# DC id); the HTTP status lands in the caller's _RP_CURL_STATUS.
#
# Not cached: the single-DC GET is already the minimal fetch, unlike the
# whole-fleet GraphQL query behind _RP_S3_DCS.
_hp_dc_tiers() {
  local dc="${1^^}" tmp status=000 tiers
  _mktemp tmp
  rp::http_soft "$tmp" GET "/catalog/datacenters/$dc" || true
  status="${_RP_CURL_STATUS:-000}"
  ((status >= 200 && status < 300)) || {
    rm -f -- "$tmp"
    return 1
  }
  # Separate declaration and assignment: `local x="$(...)"` would mask jq's
  # exit status (same trap as the rp::require_* nameref-family rule).
  tiers="$(jq -c '(.networkVolumeTypes // []) | map(ascii_upcase)' "$tmp" 2>/dev/null)" || {
    rm -f -- "$tmp"
    return 1
  }
  rm -f -- "$tmp"
  [[ "$tiers" == \[*\] ]] || return 1
  printf '%s\n' "$tiers"
}

# True when $1 (the compact tiers array from _hp_dc_tiers) lists $2. Tier
# tokens are up-cased enum values, so a quoted-substring test is exact.
_hp_tiers_have() { [[ "$1" == *'"'"$2"'"'* ]]; }

# Return 0 if $1 names a datacentre whose v2 catalog record lists the
# HIGH_PERFORMANCE network-volume tier, else 1. An unreachable catalog or an
# unknown DC id is also 1 — callers that must distinguish "known not-capable"
# from "unknown" should call _hp_dc_tiers directly.
# Arguments:
#   $1 - dc: datacentre id (case-insensitive)
# Returns:
#   0 - the DC's networkVolumeTypes lists HIGH_PERFORMANCE
#   1 - it does not, or capability is unknown
rp::is_hp_dc() {
  local tiers
  tiers="$(_hp_dc_tiers "$1")" || return 1
  _hp_tiers_have "$tiers" HIGH_PERFORMANCE
}

# Warn when a HIGH_PERFORMANCE create would target a DC whose catalog record
# does not list the tier. Warn-only (mirroring rp::warn_unless_s3_dc on
# create): the API stays the authority on capability, so creation is never
# blocked. Silent when capability is UNKNOWN — no offline fallback list of
# HP-capable DCs exists publicly, and guessing would nag users on catalog
# outages; the create POST surfaces any real rejection.
rp::warn_unless_hp_dc() {
  local tiers
  tiers="$(_hp_dc_tiers "$1")" || return 0
  _hp_tiers_have "$tiers" HIGH_PERFORMANCE ||
    rp::warn "note: datacenter '$1' does not list the HIGH_PERFORMANCE volume tier — the create request may fail (see: rp stock dc)"
}
