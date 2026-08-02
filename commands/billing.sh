#!/usr/bin/env bash
#
# `rp billing` — pod / serverless / public-endpoint / cluster / network-volume
# billing (REST API v2).
# Usage: rp billing <verb> [flags]
#
# v2 returns time-bucketed { records: [...], metadata }; both modes print it.
# Serverless spend lives at /billing/serverless (/billing/endpoints is the
# separate *public endpoint* product's billing).

# All six billing GETs are optional-param-only (no request body). $1 is the REST
# path; $2 the optional per-resource id-param name (podId/clusterId/…); when set
# the positional is read as that id. The four time-window flags apply to every
# verb. Prints v2's time-bucketed { records, metadata } envelope as JSON or
# pretty.
_billing() {
  local path="$1" idkey="${2:-}" id
  id="$(rp::args_pos)"
  local -a q=()
  [[ -n "$idkey" && -n "$id" ]] && q+=("$idkey" "$id")

  local start end bucket lastn
  start="$(rp::args_get start)"
  end="$(rp::args_get end)"
  bucket="$(rp::args_get bucket-size)"
  lastn="$(rp::args_get_uint last-n)"

  # lastN is mutually exclusive with startTime/endTime (per spec).
  if [[ -n "$lastn" && (-n "$start" || -n "$end") ]]; then
    rp::usage "--last-n is mutually exclusive with --start/--end"
  fi
  # lastN minimum is 1 (per spec); rp::require_uint only blocks non-numbers, so
  # 0 must be rejected here rather than in the shared helper (workers-min/max
  # legitimately default to 0 elsewhere).
  if [[ -n "$lastn" && "$lastn" -lt "$RP_LAST_N_MIN" ]]; then
    rp::usage "--last-n must be at least $RP_LAST_N_MIN"
  fi
  case "$bucket" in
  '' | hour | day | week | month | year) ;;
  *) rp::usage "invalid --bucket-size '$bucket' (expected hour|day|week|month|year)" ;;
  esac

  [[ -n "$start" ]] && q+=(startTime "$start")
  [[ -n "$end" ]] && q+=(endTime "$end")
  [[ -n "$bucket" ]] && q+=(bucketSize "$bucket")
  [[ -n "$lastn" ]] && q+=(lastN "$lastn")

  local body
  body="$(rp::http GET "$path$(rp::query_params "${q[@]}")")"
  rp::emit_json_or "$body" rp::json_pretty "$body"
}

rp::cmd_billing() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  pods) _billing /billing/pods podId ;;
  serverless) _billing /billing/serverless serverlessId ;;
  public-endpoints) _billing /billing/endpoints ;;
  clusters) _billing /billing/clusters clusterId ;;
  volumes) _billing /billing/networkvolumes networkVolumeId ;;
  all) _billing /billing ;;
  endpoints)
    rp::warn "'rp billing endpoints' is deprecated — use 'rp billing serverless' (serverless spend) or 'rp billing public-endpoints' (public-endpoint product)"
    _billing /billing/serverless serverlessId
    ;;
  -h | --help | help)
    echo "Usage: rp billing <pods [id] | serverless [id] | public-endpoints | clusters [id] | volumes [id] | all>"
    echo "                  [--start <rfc3339>] [--end <rfc3339>] [--bucket-size hour|day|week|month|year] [--last-n N]"
    echo "  Time flags apply to every verb; --last-n is mutually exclusive with --start/--end."
    echo "  Scoped verbs take an optional <id>: pods→podId, serverless→serverlessId,"
    echo "  clusters→clusterId, volumes→networkVolumeId. (public-endpoints and all take none.)"
    ;;
  *) rp::usage "unknown billing verb: '$verb'" ;;
  esac
}
