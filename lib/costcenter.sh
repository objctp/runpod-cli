#!/usr/bin/env bash
# Client-side cost centers: named local buckets tagging pods, serverless
# endpoints, network volumes and instant clusters, so spend can be aggregated
# per project from the per-resource billing endpoints. Runpod's own Cost
# Centers feature is console-only (no v2 REST / GraphQL surface), so the
# tagging lives in a per-user state file and never touches a cost-center API;
# only the spend roll-up is remote, reusing rp billing's endpoints.
#
# State shape (one file, per-user config dir):
#   {"centers":{"<name>":{"note":"…"}}, "assignments":{"<id>":{"type":"pod|serverless|volume|cluster|", "center":"<name>"}}}
# Every resource sits in exactly one bucket: assign/stamp overwrite the
# previous entry, deleting a bucket drops its members back to untagged.
# Locals are cc_-prefixed: tests override rp::http with doubles that read
# their own outer variables (same convention as lib/resource.sh).
[[ -n "${_RP_COSTCENTER:-}" ]] && return 0
_RP_COSTCENTER=1

# The state file's path, resolved at call time (not sourced once) so an
# RP_CONFIG_HOME reassigned after the libs load — as bin/rp does for the
# credential store, and tests do for isolation — is honoured. An explicit
# RP_COST_CENTERS_FILE wins; empty means unset.
rp::cc_file() {
  printf '%s' "${RP_COST_CENTERS_FILE:-$RP_CONFIG_HOME/cost-centers.json}"
}

# Read the state file and print it normalised to the two-key shape. A missing
# file is the empty skeleton; a corrupt or non-object file dies loudly rather
# than silently resetting the user's tagging.
rp::cc_state() {
  local cc_f cc_raw cc_norm
  cc_f="$(rp::cc_file)"
  if [[ ! -f "$cc_f" ]]; then
    printf '%s' '{"centers":{},"assignments":{}}'
    return 0
  fi
  cc_raw="$(<"$cc_f")"
  cc_norm="$(printf '%s' "$cc_raw" | jq -c '
    if type == "object" then
      {centers: (.centers // {}), assignments: (.assignments // {})}
    else
      error("expected a JSON object")
    end' 2>/dev/null)" || rp::die "cost-center state '$cc_f' is not valid JSON — fix or remove the file (it holds rp's local cost-center tagging)"
  printf '%s' "$cc_norm"
}

# Atomically replace the state file: validate, write a temp file in the target
# directory, lock it to owner-only, then rename over the target. A crash mid-
# write therefore never truncates the existing state.
rp::cc_save() {
  local cc_state="$1" cc_f cc_dir cc_tmp
  printf '%s' "$cc_state" | jq -e 'type == "object"' >/dev/null 2>&1 ||
    rp::die "refusing to save invalid cost-center state: $cc_state"
  cc_f="$(rp::cc_file)"
  cc_dir="$(dirname "$cc_f")"
  mkdir -p "$cc_dir"
  cc_tmp="$(mktemp "$cc_dir/.cost-centers.XXXXXX")"
  printf '%s\n' "$cc_state" >"$cc_tmp"
  chmod 600 "$cc_tmp"
  mv -f "$cc_tmp" "$cc_f"
}

# Print the cost-center names in creation order.
rp::cc_names() {
  rp::cc_state | jq -r '.centers | keys_unsorted[]'
}

# Print the resource ids tagged to $1, one per line.
rp::cc_members() {
  rp::cc_state | jq -r --arg n "$1" '
    .assignments | to_entries[] | select(.value.center == $n) | .key'
}

# Print the stored type of $1 (pod | serverless | volume | cluster | empty).
rp::cc_type_of() {
  rp::cc_state | jq -r --arg i "$1" '.assignments[$i].type // ""'
}

# True (0) when cost center $1 exists.
rp::cc_exists() {
  jq -e --arg n "$1" '.centers | has($n)' <<<"$(rp::cc_state)" >/dev/null
}

# Die with not-found unless cost center $1 exists.
rp::cc_require_center() {
  rp::cc_exists "$1" ||
    rp::notfound "cost center '$1' not found — create it first: rp cost-center create $1"
}

# Create a cost center (idempotent on the name, like the API creates). $2 is
# an optional note; a re-create never overwrites the stored note.
rp::cc_create() {
  local cc_name="${1:-}" cc_note="${2:-}" cc_state
  [[ -n "$cc_name" ]] || rp::usage "usage: rp cost-center create <name> [--note <text>]"
  cc_state="$(rp::cc_state)"
  rp::cc_exists "$cc_name" && return 0
  cc_state="$(jq -c --arg n "$cc_name" --arg note "$cc_note" \
    '.centers[$n] = (if $note == "" then {} else {note: $note} end)' <<<"$cc_state")"
  rp::cc_save "$cc_state"
}

# Delete a cost center: the bucket goes and its members return to the
# untagged pool (Runpod's console semantics for deleting a cost center).
rp::cc_delete() {
  local cc_name="${1:-}" cc_state
  [[ -n "$cc_name" ]] || rp::usage "usage: rp cost-center delete <name>"
  rp::cc_require_center "$cc_name"
  cc_state="$(rp::cc_state)"
  cc_state="$(jq -c --arg n "$cc_name" '
    del(.centers[$n])
    | .assignments |= with_entries(select(.value.center != $n))' <<<"$cc_state")"
  rp::cc_save "$cc_state"
}

# Assign ids to a cost center, moving each id out of any previous bucket.
# Ids whose type is not already stored are classified by probing the four
# resource lists once (rp::cc_detect_types); an id no list knows is still
# recorded, with an empty type, so its spend keeps resolving later — spend
# then bills it against every product instead of one.
rp::cc_assign() {
  local cc_center="$1"
  shift || true
  (($#)) || rp::usage "usage: rp cost-center assign <name> <id>…"
  rp::cc_require_center "$cc_center"
  local cc_state cc_id cc_type
  cc_state="$(rp::cc_state)"
  local -A cc_type_of=()
  for cc_id in "$@"; do
    rp::require_id cc_id "$cc_id" "resource id"
    cc_type_of["$cc_id"]="$(jq -r --arg i "$cc_id" '.assignments[$i].type // ""' <<<"$cc_state")"
  done
  local -a cc_unknown=()
  for cc_id in "${!cc_type_of[@]}"; do
    [[ -z "${cc_type_of[$cc_id]}" ]] && cc_unknown+=("$cc_id")
  done
  if ((${#cc_unknown[@]})); then
    while IFS=$'\t' read -r cc_id cc_type; do
      [[ -n "$cc_id" ]] || continue
      cc_type_of["$cc_id"]="$cc_type"
    done < <(rp::cc_detect_types "${cc_unknown[@]}")
  fi
  for cc_id in "$@"; do
    cc_state="$(jq -c --arg i "$cc_id" --arg t "${cc_type_of[$cc_id]}" --arg c "$cc_center" \
      '.assignments[$i] = {type: $t, center: $c}' <<<"$cc_state")"
  done
  rp::cc_save "$cc_state"
}

# Assign with a known type and no probing — the seam create verbs use at
# assign-at-create, where the resource type is known by construction.
rp::cc_stamp() {
  local cc_center="$1" cc_type="$2" cc_id="$3" cc_state
  rp::cc_require_center "$cc_center"
  cc_state="$(rp::cc_state)"
  cc_state="$(jq -c --arg i "$cc_id" --arg t "$cc_type" --arg c "$cc_center" \
    '.assignments[$i] = {type: $t, center: $c}' <<<"$cc_state")"
  rp::cc_save "$cc_state"
}

# Remove ids from every bucket (no-op for ids that were never assigned).
rp::cc_unassign() {
  (($#)) || rp::usage "usage: rp cost-center unassign <id>…"
  local cc_state cc_id
  cc_state="$(rp::cc_state)"
  for cc_id in "$@"; do
    rp::require_id cc_id "$cc_id" "resource id"
    cc_state="$(jq -c --arg i "$cc_id" 'del(.assignments[$i])' <<<"$cc_state")"
  done
  rp::cc_save "$cc_state"
}

# Tag a just-created resource (used by rp::resource_create's --cost-center
# hook). Quiet no-op without a center. Failure inside is downgraded to a
# warning in a subshell — the resource already exists, so a state-write error
# must not fail the create; the message names the follow-up assign.
rp::cc_tag_quietly() {
  local cc_center="$1" cc_type="$2" cc_id="$3"
  [[ -n "$cc_center" ]] || return 0
  case "$cc_type" in
  pod | serverless | volume | cluster) ;;
  *) rp::die "cost centers apply to pods, serverless endpoints, network volumes and clusters only (got: $cc_type)" ;;
  esac
  (rp::cc_stamp "$cc_center" "$cc_type" "$cc_id") 2>/dev/null ||
    rp::warn "could not record cost center '$cc_center' for $cc_id — run: rp cost-center assign $cc_center $cc_id"
}

# Classify ids against the four resource lists: prints one "<id><TAB><type>"
# line per input id, type empty when no list knows it (terminated/deleted
# resources, or ids beyond a list's first page — harmless, since spend then
# bills those against every product). Four GETs total, whatever the id count.
rp::cc_detect_types() {
  local cc_pod cc_srv cc_vol cc_clu cc_id cc_t
  cc_pod="$(rp::http GET /pods | rp::unwrap pods | jq -r 'map(.id // empty) | join("\n")' 2>/dev/null)" || cc_pod=""
  cc_srv="$(rp::http GET /serverless | rp::unwrap endpoints | jq -r 'map(.id // empty) | join("\n")' 2>/dev/null)" || cc_srv=""
  cc_vol="$(rp::http GET /network-volumes | rp::unwrap networkVolumes | jq -r 'map(.id // empty) | join("\n")' 2>/dev/null)" || cc_vol=""
  cc_clu="$(rp::http GET /clusters | rp::unwrap clusters | jq -r 'map(.id // empty) | join("\n")' 2>/dev/null)" || cc_clu=""
  for cc_id in "$@"; do
    cc_t=""
    if printf '%s\n' "$cc_pod" | grep -qxF -- "$cc_id"; then
      cc_t=pod
    elif printf '%s\n' "$cc_srv" | grep -qxF -- "$cc_id"; then
      cc_t=serverless
    elif printf '%s\n' "$cc_vol" | grep -qxF -- "$cc_id"; then
      cc_t=volume
    elif printf '%s\n' "$cc_clu" | grep -qxF -- "$cc_id"; then
      cc_t=cluster
    fi
    printf '%s\t%s\n' "$cc_id" "$cc_t"
  done
}

# The billing endpoint that reports a resource's spend: prints one
# "<path>|<idParam>" line per target. A typed id bills against its one
# product; an unknown type bills against all four (an id can only appear in
# its own product's report, so the sum is still exact).
rp::cc_billing_targets() {
  case "$1" in
  pod) printf '%s\n' "/billing/pods|podId" ;;
  serverless) printf '%s\n' "/billing/serverless|serverlessId" ;;
  volume) printf '%s\n' "/billing/network-volumes|networkVolumeId" ;;
  cluster) printf '%s\n' "/billing/clusters|clusterId" ;;
  *)
    printf '%s\n' "/billing/pods|podId" "/billing/serverless|serverlessId" \
      "/billing/network-volumes|networkVolumeId" "/billing/clusters|clusterId"
    ;;
  esac
}
