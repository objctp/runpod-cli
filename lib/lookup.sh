#!/usr/bin/env bash
# Resolve a resource name to its id via REST list + jq filter (volume / endpoint / pod / template / registry).
[[ -n "${_RP_LOOKUP:-}" ]] && return 0
_RP_LOOKUP=1

rp::lookup_id() {
  local resource="$1"
  local name="$2"
  local path
  case "$resource" in
  volume) path=/networkvolumes ;;
  endpoint) path=/endpoints ;;
  pod) path=/pods ;;
  template) path=/templates ;;
  registry) path=/containerregistryauth ;;
  *) rp::usage "lookup unsupported for '$resource'" ;;
  esac
  rp::http GET "$path" |
    jq -r --arg n "$name" '
        def arr: if type == "array" then .
                 elif type == "object" then (.data // .networkVolumes // .pods // .endpoints // .templates // .containerRegistryAuths // [])
                 else [] end;
        arr | map(select(.name == $n)) | .[0].id // empty'
}
