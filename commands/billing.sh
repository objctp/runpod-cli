#!/usr/bin/env bash
#
# Spend reports for pods, serverless, clusters and volumes.
#
# Every verb reads the same v2 billing envelope — a records array of per-bucket
# totals plus a metadata object — over one time window, and the four window
# flags apply to all of them. Verbs differ only in the product they report and
# whether they narrow to a single resource id. Serverless spend lives at
# /billing/serverless; /billing/endpoints is the separate *public endpoint*
# product, reached as `rp billing public-endpoints`.
#
# Usage: rp billing <verb> [flags]
#

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

###
### :::: documentation (rp doc billing) :::: ##################################
###

# doc: pods
# Report pod spend, optionally for one pod.
#
# Usage: rp billing pods [<id>] [--start <rfc3339>] [--end <rfc3339>]
#                        [--bucket-size hour|day|week|month|year]
#                        [--last-n N] [--json]
#
# Arguments:
#   <id>                                    pod id; omit for every pod
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   The response is v2's time-bucketed envelope — a records array plus a
#   metadata object — printed whole in both output modes.
#   Terminated pods still appear. This is billing history, not an inventory of
#   what is running now.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#   --bucket-size takes hour, day, week, month or year; anything else is a
#   usage error raised before the request goes out.
#   Omitting all four window flags returns the account's whole pod history,
#   which is slow and noisy on a long-lived account.
#
# Examples:
#   rp billing pods --last-n 7 --bucket-size day
#   rp billing pods pod_abc123 --start 2026-07-01T00:00:00Z
#
# API: GET /v2/billing/pods

# doc: serverless
# Report serverless spend, optionally for one endpoint.
#
# Usage: rp billing serverless [<id>] [--start <rfc3339>] [--end <rfc3339>]
#                              [--bucket-size hour|day|week|month|year]
#                              [--last-n N] [--json]
#
# Arguments:
#   <id>                                    serverless endpoint id; omit for
#                                           every endpoint
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   This is spend on your own serverless endpoints. Runpod's hosted public
#   endpoint product is billed separately, under
#   `rp billing public-endpoints`.
#   <id> is an endpoint id from `rp serverless list`, sent as serverlessId.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#   --bucket-size takes hour, day, week, month or year.
#
# Examples:
#   rp billing serverless --last-n 24 --bucket-size hour
#   rp billing serverless ep_xyz789 --bucket-size day --json
#
# API: GET /v2/billing/serverless

# doc: public-endpoints
# Report spend on the public endpoint product.
#
# Usage: rp billing public-endpoints [--start <rfc3339>] [--end <rfc3339>]
#                                    [--bucket-size hour|day|week|month|year]
#                                    [--last-n N] [--json]
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   Public endpoints are Runpod's own hosted inference APIs, billed as their
#   own product. This is not spend on endpoints you deployed — that is
#   `rp billing serverless`.
#   The verb takes no id: the API offers no filter for this product, so the
#   whole account's history comes back. A positional argument is accepted and
#   ignored.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#
# Examples:
#   rp billing public-endpoints --last-n 30 --bucket-size day
#
# API: GET /v2/billing/endpoints

# doc: clusters
# Report instant cluster spend, optionally for one cluster.
#
# Usage: rp billing clusters [<id>] [--start <rfc3339>] [--end <rfc3339>]
#                            [--bucket-size hour|day|week|month|year]
#                            [--last-n N] [--json]
#
# Arguments:
#   <id>                                    cluster id; omit for every cluster
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   Instant clusters are multi-node GPU deployments. The CLI has no verb that
#   creates or lists them, so the id has to come from the console or from a
#   record in an earlier report.
#   <id> is sent as clusterId.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#
# API: GET /v2/billing/clusters

# doc: volumes
# Report network volume spend, optionally for one volume.
#
# Usage: rp billing volumes [<id>] [--start <rfc3339>] [--end <rfc3339>]
#                           [--bucket-size hour|day|week|month|year]
#                           [--last-n N] [--json]
#
# Arguments:
#   <id>                                    network volume id; omit for every
#                                           volume
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   <id> is a volume id from `rp volume list`, sent as networkVolumeId. Unlike
#   the S3 verbs of `rp volume`, this takes no name and resolves nothing.
#   A volume bills for its provisioned capacity whether or not anything mounts
#   it, so deleted pods do not end the charge — deleting the volume does.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#
# Examples:
#   rp billing volumes --last-n 12 --bucket-size month
#
# API: GET /v2/billing/networkvolumes

# doc: all
# Report aggregated spend across every product.
#
# Usage: rp billing all [--start <rfc3339>] [--end <rfc3339>]
#                       [--bucket-size hour|day|week|month|year]
#                       [--last-n N] [--json]
#
# Options:
#   --start <rfc3339>                       window start, inclusive
#   --end <rfc3339>                         window end, exclusive
#   --bucket-size hour|day|week|month|year  size of each record's bucket
#   --last-n N                              the last N buckets instead of a
#                                           window; minimum 1
#   --json                                  print the raw API response
#
# Notes:
#   Each record totals the account across products, so this is the number to
#   reconcile against an invoice; the per-product verbs are where a total gets
#   broken down.
#   The verb takes no id, and a positional argument is accepted and ignored.
#   --last-n counts back from now in whole buckets. It cannot be combined with
#   --start or --end, and its minimum is 1.
#
# Examples:
#   rp billing all --last-n 6 --bucket-size month
#
# API: GET /v2/billing

# doc: endpoints
# Deprecated: use `rp billing serverless` instead.
#
# Usage: rp billing endpoints
#
# Notes:
#   The verb predates the endpoint-to-serverless rename and now maps to
#   serverless spend: it warns, then does exactly what `rp billing serverless`
#   does, positional id and window flags included.
#   Should you have wanted the *public endpoint* product rather than your own
#   endpoints' spend, that is `rp billing public-endpoints` — the name is a
#   trap, which is why this alias warns rather than guessing.
#
# API: GET /v2/billing/serverless

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
