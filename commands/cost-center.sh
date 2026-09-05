#!/usr/bin/env bash
#
# Client-side cost centers: named buckets for per-project spend.
#
# Runpod's own Cost Centers are console-only (no v2 REST or GraphQL surface),
# so the tagging lives in a per-user state file and only the spend roll-up is
# remote, reusing the per-resource billing endpoints behind `rp billing`.
# Every resource sits in exactly one bucket; untagged resources are
# "Uncategorized", matching the console. Because the tagging is local, it
# survives a resource's deletion — a bucket's spend history keeps resolving by
# id after the API-side object is gone, which the live lists no longer show.
#
# Usage: rp cost-center <verb> [flags]
#

# Print the positionals from index $1 onward, one per line (verbs that take an
# id list after the center name).
_cc_tail_positionals() {
  local cc_i
  for ((cc_i = ${1:-0}; cc_i < ${#RP_POSITIONALS[@]}; cc_i++)); do
    printf '%s\n' "${RP_POSITIONALS[cc_i]}"
  done
}

_cc_create() {
  local name
  rp::require_pos name "usage: rp cost-center create <name> [--note <text>]"
  if rp::cc_exists "$name"; then
    rp::ok "cost center '$name' exists"
  else
    rp::cc_create "$name" "$(rp::args_get note)"
    rp::ok "created cost center '$name'"
  fi
}

_cc_list() {
  local cc_state cc_rows jqf
  cc_state="$(rp::cc_state)"
  cc_rows="$(jq -c '
    . as $s
    | [$s.centers | to_entries[] | . as $c | {
        name: $c.key,
        note: ($c.value.note // ""),
        resources: ([$s.assignments | to_entries[] | select(.value.center == $c.key)] | length)
      }]' <<<"$cc_state")"
  jqf="$(rp::args_get jq)"
  [[ -z "$jqf" ]] || cc_rows="$(jq -c "$jqf" <<<"$cc_rows")" || rp::die "invalid --jq filter: $jqf"
  rp::emit_json_or "$cc_rows" rp::table "$cc_rows" name note resources
}

_cc_assign() {
  local center
  rp::require_pos center "usage: rp cost-center assign <name> <id>…"
  local -a ids=()
  mapfile -t ids < <(_cc_tail_positionals 1)
  ((${#ids[@]})) || rp::usage "usage: rp cost-center assign <name> <id>…"
  rp::cc_assign "$center" "${ids[@]}"
  rp::ok "assigned ${#ids[@]} resource(s) to cost center '$center'"
}

_cc_unassign() {
  local -a ids=()
  mapfile -t ids < <(_cc_tail_positionals 0)
  ((${#ids[@]})) || rp::usage "usage: rp cost-center unassign <id>…"
  rp::cc_unassign "${ids[@]}"
  rp::ok "unassigned ${#ids[@]} resource(s)"
}

_cc_delete() {
  local name
  rp::require_pos name "usage: rp cost-center delete <name>"
  rp::cc_delete "$name"
  rp::ok "deleted cost center '$name' (its resources are untagged)"
}

# Bill one resource over _CC_WINDOW: one call per billing target (its own
# product when typed, all four when the type is unknown), summed.
_cc_bill_resource() {
  local cc_id="$1" cc_type="$2" cc_path cc_key cc_body cc_t cc_total=0
  while IFS='|' read -r cc_path cc_key; do
    [[ -n "$cc_path" ]] || continue
    cc_body="$(rp::http GET "$cc_path$(rp::query_params "$cc_key" "$cc_id" "${_CC_WINDOW[@]}")")"
    cc_t="$(jq -r '(.metadata.totals.totalAmount // ([.records[]?.totalAmount] | add) // 0)' <<<"$cc_body")"
    cc_total="$(jq -n --argjson a "$cc_total" --argjson b "$cc_t" '$a + $b')"
  done < <(rp::cc_billing_targets "$cc_type")
  printf '%s' "$cc_total"
}

# Build one bucket's breakdown JSON: {name, total, resources:[{id,type,total}]}.
# The bucket's "id<TAB>type" lines arrive on stdin; _CC_WINDOW carries the
# validated query pairs.
_cc_center_json() {
  local cc_name="$1" cc_id cc_type cc_total cc_res='[]' cc_sum=0
  while IFS=$'\t' read -r cc_id cc_type; do
    [[ -n "$cc_id" ]] || continue
    cc_total="$(_cc_bill_resource "$cc_id" "$cc_type")"
    cc_res="$(jq -c --arg id "$cc_id" --arg type "$cc_type" --argjson t "$cc_total" \
      '. + [{id: $id, type: (if $type == "" then null else $type end), total: $t}]' <<<"$cc_res")"
    cc_sum="$(jq -n --argjson a "$cc_sum" --argjson b "$cc_total" '$a + $b')"
  done
  jq -cn --arg n "$cc_name" --argjson res "$cc_res" --argjson total "$cc_sum" \
    '{name: $n, total: $total, resources: $res}'
}

# The untagged pool for the whole-account view: every id in the four resource
# lists that is not assigned to any bucket, one "id<TAB>type" line each.
_cc_uncategorized() {
  local cc_assigned cc_pairs
  cc_assigned="$(rp::cc_state | jq -c '[.assignments | keys[]]')"
  cc_pairs="$(
    {
      rp::http GET /pods | rp::unwrap pods | jq -r 'map(.id // empty)[] | "\(.)\tpod"' 2>/dev/null || true
      rp::http GET /serverless | rp::unwrap endpoints | jq -r 'map(.id // empty)[] | "\(.)\tserverless"' 2>/dev/null || true
      rp::http GET /network-volumes | rp::unwrap networkVolumes | jq -r 'map(.id // empty)[] | "\(.)\tvolume"' 2>/dev/null || true
      rp::http GET /clusters | rp::unwrap clusters | jq -r 'map(.id // empty)[] | "\(.)\tcluster"' 2>/dev/null || true
    }
  )"
  # The pairs are raw TSV, so the assigned filter runs on a slurped TSV→JSON
  # conversion; untagged ids pass through unchanged (-r for raw output lines).
  printf '%s\n' "$cc_pairs" | jq -Rsr --argjson assigned "$cc_assigned" '
    split("\n")
    | map(select(length > 0) | split("\t") | {id: .[0], type: .[1]})
    | map(select((.id as $i | ($assigned | index($i))) == null))
    | .[] | "\(.id)\t\(.type)"'
}

# Human view of the spend roll-up: one row per bucket plus a TOTAL row.
_cc_spend_human() {
  local cc_agg="$1" cc_rows
  cc_rows="$(jq -c '
    [.centers[] | {name, resources: (.resources | length), total}]
    + [{name: "TOTAL",
        resources: ([.centers[] | .resources | length] | add // 0),
        total: .total}]' <<<"$cc_agg")"
  rp::table "$cc_rows" name resources total
}

# Spend roll-up. With a name: just that bucket. Without: every bucket plus the
# Uncategorized pool (which needs the four resource lists to enumerate).
_cc_spend() {
  local cc_name
  cc_name="$(rp::args_pos)"
  _CC_WINDOW=()
  rp::billing_window_query _CC_WINDOW "rp cost-center spend"
  [[ -z "$cc_name" ]] || rp::cc_require_center "$cc_name"

  local cc_state cc_parts=() cc_part cc_unc='null' cc_agg
  cc_state="$(rp::cc_state)"
  if [[ -n "$cc_name" ]]; then
    cc_part="$(_cc_center_json "$cc_name" < <(
      jq -r --arg n "$cc_name" '
        .assignments | to_entries[] | select(.value.center == $n)
        | "\(.key)\t\(.value.type // "")"' <<<"$cc_state"
    ))"
    cc_parts+=("$cc_part")
  else
    while IFS= read -r cc_part; do
      [[ -n "$cc_part" ]] || continue
      cc_parts+=("$cc_part")
    done < <(jq -r '.centers | keys_unsorted[]' <<<"$cc_state" | while IFS= read -r cc_center; do
      _cc_center_json "$cc_center" < <(
        jq -r --arg n "$cc_center" '
          .assignments | to_entries[] | select(.value.center == $n)
          | "\(.key)\t\(.value.type // "")"' <<<"$cc_state"
      )
    done)
    cc_unc="$(_cc_center_json "Uncategorized" < <(_cc_uncategorized))"
    # Keep the Uncategorized row only when the pool is non-empty.
    jq -e '.resources | length > 0' <<<"$cc_unc" >/dev/null && cc_parts+=("$cc_unc")
  fi

  local cc_centers='[]'
  if ((${#cc_parts[@]})); then
    cc_centers="$(printf '%s\n' "${cc_parts[@]}" | jq -cs '.')"
  fi
  cc_agg="$(jq -cn --argjson centers "$cc_centers" \
    '{centers: $centers, total: ($centers | map(.total) | add // 0)}')"
  rp::emit_json_or "$cc_agg" _cc_spend_human "$cc_agg"
}

###
### :::: documentation (rp doc cost-center) :::: ##############################
###

# doc: create
# Create a cost center: a named bucket for tagging resources.
#
# Usage: rp cost-center create <name> [--note <text>]
#
# Arguments:
#   <name>           cost center name; local to this machine
#
# Options:
#   --note <text>    free-text note shown by `rp cost-center list`
#
# Notes:
#   Runpod's own Cost Centers are console-only, so `rp` keeps its cost centers
#   locally: the buckets and their resource tags live in a per-user state file
#   and only the spend roll-up talks to the API. Creating is idempotent on the
#   name — an existing center is reported, never modified; delete and re-create
#   to change its note.
#
# Examples:
# # Create a bucket per client
# $ rp cost-center create freelance --note "client work"
# # Create one per project on a solo account
# $ rp cost-center create rag-pipeline
#
# API: none (local state: $RP_CONFIG_HOME/cost-centers.json)

# doc: list
# List cost centers: name, note, and how many resources each one tags.
#
# Usage: rp cost-center list [--json] [--jq <filter>]
#
# Options:
#   --json           print the rows as JSON
#   --jq <filter>    jq filter applied to the rows array
#
# Notes:
#   The resource count covers tagged ids only. See which ids with --jq:
#   `rp cost-center list --json` prints the rows; the ids themselves come from
#   the spend breakdown (`rp cost-center spend <name> --json`).
#
# API: none (local state: $RP_CONFIG_HOME/cost-centers.json)

# doc: assign
# Tag resources to a cost center, moving them out of any previous one.
#
# Usage: rp cost-center assign <name> <id>…
#
# Arguments:
#   <name>           cost center to tag into (create it first)
#   <id>…            one or more pod / endpoint / volume / cluster ids
#
# Notes:
#   A resource sits in exactly one cost center: assigning an already-tagged id
#   moves it. Ids are classified by reading the pod, serverless, volume and
#   cluster lists (one pass), and a type is remembered per id so spend can bill
#   against the right product. An id no list knows is still recorded — its type
#   stays unknown and spend then bills it against every product, which still
#   sums correctly because an id only appears in its own product's report.
#   Tagging is local, so it works on terminated or deleted resources too; their
#   billing history keeps resolving by id.
#
# Examples:
# # Put a pod and an endpoint into the same project bucket
# $ rp cost-center assign rag-pipeline pod_abc123 ep-7f2a
#
# API: GET /v2/pods, GET /v2/serverless, GET /v2/network-volumes,
#      GET /v2/clusters (id classification only)

# doc: unassign
# Remove resources from every cost center (they become Uncategorized).
#
# Usage: rp cost-center unassign <id>…
#
# Arguments:
#   <id>…            one or more resource ids to untag
#
# Notes:
#   Unknown ids are ignored, so the verb is safe to re-run.
#
# API: none (local state: $RP_CONFIG_HOME/cost-centers.json)

# doc: delete
# Delete a cost center; its resources return to the untagged pool.
#
# Usage: rp cost-center delete <name>
#
# Arguments:
#   <name>           cost center to remove
#
# Notes:
#   Mirrors the console: deleting a cost center does not touch the resources,
#   it only removes the bucket, and previously tagged ids become Uncategorized.
#
# API: none (local state: $RP_CONFIG_HOME/cost-centers.json)

# doc: spend
# Report spend per cost center, rolled up from the billing endpoints.
#
# Usage: rp cost-center spend [<name>] [--start <rfc3339>] [--end <rfc3339>]
#                             [--bucket-size hour|day|week|month|year]
#                             [--last-n N] [--json]
#
# Arguments:
#   <name>                                    cost center; omit for every
#                                             center plus Uncategorized
#
# Options:
#   --start <rfc3339>                         window start, inclusive
#   --end <rfc3339>                           window end, exclusive
#   --bucket-size hour|day|week|month|year    size of each billing bucket
#   --last-n N                                the last N buckets instead of a
#                                             window; minimum 1
#   --json                                    print the full per-resource
#                                             breakdown as JSON
#
# Notes:
#   Each bucket's total is the sum of its members' spend, each read from the
#   same v2 billing endpoints `rp billing` uses — one call per typed resource.
#   An id whose type is unknown (recorded before its resource listable, or
#   assigned by hand) is billed against every product; the sum stays correct
#   because an id only appears in its own product's report.
#   Without <name>, every bucket is reported plus Uncategorized — every
#   resource the lists know that is tagged nowhere. The whole-account view
#   covers resources that still exist; a deleted resource's history remains
#   reachable inside the bucket it was tagged to.
#   --last-n is mutually exclusive with --start/--end, exactly as in
#   `rp billing`.
#
# Examples:
# # Per-project spend over the last month, daily
# $ rp cost-center spend --last-n 1 --bucket-size month
# # One project's spend since July
# $ rp cost-center spend rag-pipeline --start 2026-07-01T00:00:00Z
# # Full breakdown as JSON
# $ rp cost-center spend rag-pipeline --json
#
# API: GET /v2/billing/pods, GET /v2/billing/serverless,
#      GET /v2/billing/network-volumes, GET /v2/billing/clusters

rp::cmd_cost_center() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  create) _cc_create ;;
  list) _cc_list ;;
  assign) _cc_assign ;;
  unassign) _cc_unassign ;;
  delete) _cc_delete ;;
  spend) _cc_spend ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp cost-center <verb> [flags]
  create <name> [--note <t>]    create a local cost center
  list [--json] [--jq <f>]      list centers: name, note, resource count
  assign <name> <id>…           tag resources (moves them from any other center)
  unassign <id>…                remove resources from every center
  delete <name>                 drop the center; its resources become untagged
  spend [name] [--start <t>] [--end <t>] [--bucket-size <s>] [--last-n N]
                                per-project spend, rolled up from rp billing
EOF
    ;;
  *) rp::usage "unknown cost-center verb: '$verb'" ;;
  esac
}
