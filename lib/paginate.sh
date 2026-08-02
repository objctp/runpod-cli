#!/usr/bin/env bash
# Client-side pagination + field selection for list verbs. RunPod's REST v2 has
# no server-side pagination yet (the official MCP server caps client-side with a
# limit/cursor signature explicitly "shaped to match the cursor-based pagination
# the REST API will add"), so this slices an already-fetched array. The flags
# mirror that future shape: --limit caps output, --cursor is the opaque offset
# for the next page. When server pagination lands, the same flags forward to the
# API and this helper becomes a pass-through — the interface (and callers) stay.
# Reads --limit / --cursor / --jq from RP_ARGS, set by the calling verb's
# args_parse. Deliberately a standalone module, not folded into the thin
# rp::http facade, so the depth (slice + next-cursor hint) lives in one place
# shared by rp::resource_list, rp::resource_get, and rp api.
[[ -n "${_RP_PAGINATE:-}" ]] && return 0
_RP_PAGINATE=1

# Slice a JSON array in place (nameref $1) by --limit / --cursor. A non-array
# payload is left untouched (so object-wrapped or single records pass through).
# When truncated, prints a "next cursor" hint to stderr so --json stdout stays
# clean. Bad --limit/--cursor values call rp::usage (exit 2) in the caller's
# shell — the caller must not wrap this in command substitution.
rp::paginate() {
  local -n paginate_out="$1"
  local original="$paginate_out"
  local limit cursor
  limit="$(rp::args_get limit)"
  cursor="$(rp::args_get cursor)"
  [[ -z "$limit" ]] || rp::require_uint "$limit" limit
  [[ -z "$cursor" ]] || rp::require_uint "$cursor" cursor
  local skip="${cursor:-0}" take="${limit:-0}"
  paginate_out="$(printf '%s' "$original" | jq -c \
    --argjson skip "$skip" --argjson take "$take" \
    'if type == "array"
     then (. | (if $skip > 0 then .[$skip:] else . end)
               | (if $take > 0 then .[0:$take] else . end))
     else . end')" || return 1
  if [[ -n "$limit" ]]; then
    local total remaining next
    total="$(printf '%s' "$original" | jq -c 'if type == "array" then length else 1 end')"
    remaining=$((total - skip - take))
    if ((remaining > 0)); then
      next=$((skip + take))
      rp::info "more items available — next cursor: $next (total $total)"
    fi
  fi
}
