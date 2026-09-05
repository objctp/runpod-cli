#!/usr/bin/env bash
# jq-backed JSON builders (string / array / object / merge) used to assemble REST request bodies, plus rp::json_pretty for human-mode output.
[[ -n "${_RP_JSON:-}" ]] && return 0
_RP_JSON=1

_json_merge() { jq -c -n --argjson a "$1" --argjson b "$2" '$a * $b'; }

rp::json_str() { jq -Rc . <<<"$1"; }

rp::json_pretty() { jq . <<<"$1"; }

rp::json_array() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@" | jq -R . | jq -sc .
  else
    printf '[]'
  fi
}

# Build a JSON object from alternating key/value pairs.
# Arguments:
#   $1 $3 $5 … - key: object key
#   $2 $4 $6 … - value: PRE-ENCODED JSON (it lands in `jq --argjson`)
# Returns:
#   0 - prints the assembled object to stdout
# Wrap raw strings with rp::json_str first, or jq fails at runtime.
rp::json_obj() {
  local obj='{}'
  local k v
  while [[ $# -ge 2 ]]; do
    k="$1"
    v="$2"
    shift 2
    obj="$(jq -c -n --argjson cur "$obj" --arg k "$k" --argjson v "$v" '$cur + {($k): $v}')"
  done
  printf '%s' "$obj"
}

# Merge {key: val} into the object named by $1.
# Arguments:
#   $1 - dest: caller's variable name (nameref) to merge into
#   $2 - key: object key
#   $3 - val: value; an empty $3 is a silent no-op
# Returns:
#   0 - merged (or no-op when $3 is empty)
# The silent empty-skip is what request-body assembly relies on to skip unset fields.
rp::obj_set() {
  local -n dest="$1"
  local key="$2" val="$3"
  [[ -n "$val" ]] || return 0
  dest="$(_json_merge "$dest" "$(rp::json_obj "$key" "$val")")"
}

# Like rp::obj_set, but the value is read from the FILE at $3 (its raw bytes
# become the JSON string value) so a SECRET never reaches jq's command line.
# jq's argv is visible in `ps` for the process lifetime, so passing a registry
# password via --argjson would leak it; --rawfile reads the file by path instead
# (only the path, not the secret, lands on argv). $1 nameref dest, $2 key,
# $3 path to a temp file holding the secret. The file's contents are not echoed
# onto argv by this function.
rp::obj_set_secret() {
  local -n dest="$1"
  local key="$2" file="$3"
  dest="$(printf '%s' "$dest" | jq -c --arg k "$key" --rawfile v "$file" '. + {($k): $v}')"
}

# Parse newline-delimited K=V pairs (one per --env) into a JSON object. Each
# pair splits on the FIRST '=' only, so a value may itself contain '=' or ','
# (e.g. --env LIST=a,b -> {"LIST":"a,b"}). Blank lines are skipped.
rp::env_to_json() {
  local obj='{}' pair k v
  while IFS= read -r pair; do
    [[ -z "$pair" ]] && continue
    k="${pair%%=*}"
    v="${pair#*=}"
    # A `--env =value` pair yields an empty key; reject it rather than emitting
    # a `{"": "value"}` object that the API would reject cryptically.
    [[ -n "$k" ]] || rp::usage "usage: invalid --env pair (missing key): '$pair'"
    obj="$(_json_merge "$obj" "$(rp::json_obj "$k" "$(rp::json_str "$v")")")"
  done <<<"$1"
  printf '%s' "$obj"
}

# Overlay newline-delimited K=V pairs onto the `.env` map of an object.
# Arguments:
#   $1 - dest: caller's variable name (nameref) holding a JSON object
#   $2 - pairs: newline-delimited K=V (rp::env_to_json shape); empty is a no-op
# Returns:
#   0 - dest gains the merged env; keys in $2 win, untouched keys survive
# Shallow overlay, not replacement: a template's env stays intact except for the
# keys the user set (rp::obj_set would clobber the whole map).
rp::obj_merge_env() {
  local -n dest="$1"
  [[ -n "$2" ]] || return 0
  local envuser
  envuser="$(rp::env_to_json "$2")"
  dest="$(printf '%s' "$dest" | jq -c --argjson u "$envuser" '.env = ((.env // {}) * $u)')"
}

rp::csv_to_jsonarray() {
  local -a a
  mapfile -t a < <(rp::split_csv "$1")
  rp::json_array "${a[@]}"
}

# v2 ContainerConfig.args is a single entrypoint-arguments string (v1 took an
# array); join the legacy CSV flag shape (--start-cmd/--docker-cmd) with spaces.
rp::csv_to_argstring() {
  rp::split_csv "$1" | paste -sd' ' -
}

# Named request-body shapes (REST v2).
# Leaf builders for the API object shapes that were previously hand-rolled as
# inline `jq -nc` in command files. Keeping them here routes every request body
# through one seam and makes each shape unit-testable in isolation.

# Pod GPU: {id, count}.
rp::json_gpu_pod() { rp::json_obj id "$(rp::json_str "$1")" count "$2"; }

# Pod CPU: {id, vcpuCount}. vcpuCount must be a power of two >= 2 (validated by
# the caller); pure mirror of rp::json_gpu_pod.
rp::json_cpu() { rp::json_obj id "$(rp::json_str "$1")" vcpuCount "$2"; }

# Serverless GPU: {pools:[...], count}, or {pools:[...], excludedTypes:[...],
# count} when $3 carries the GPU type ids to subtract from the pools (empty
# tokens skipped). excludedTypes is a subtractive filter on `pools` — the v2
# endpoint shape has no inclusive GPU allowlist, only pool selection.
rp::json_gpu_endpoint() {
  if [[ -n "${3:-}" ]]; then
    local excluded
    excluded="$(rp::split_csv "$3" | jq -R 'select(length>0)' | jq -sc .)"
    rp::json_obj pools "$(rp::csv_to_jsonarray "$1")" excludedTypes "$excluded" count "$2"
  else
    rp::json_obj pools "$(rp::csv_to_jsonarray "$1")" count "$2"
  fi
}

# Worker scaling: {min, max, idleTimeout?}, omitting any empty field.
# Arguments:
#   $1 - min workers (int>=0, optional)
#   $2 - max workers (int>=0, optional)
#   $3 - idleTimeout (int 1-3600, optional); an empty value is a silent no-op
rp::json_workers() {
  local obj='{}'
  rp::obj_set obj min "$1"
  rp::obj_set obj max "$2"
  rp::obj_set obj idleTimeout "$3"
  printf '%s' "$obj"
}

# v2 EndpointScaling discriminated union on `type`.
# Arguments:
#   $1 - scaler type: QUEUE_DELAY | REQUEST_COUNT
#   $2 - value: float seconds (queueDelay, minimum 0.5) or int (requestCount, minimum 1)
# Returns:
#   0 - the matching union arm; prints JSON to stdout
#   2 - unknown scaler type (rp::usage)
rp::json_scaling() {
  case "$1" in
  QUEUE_DELAY) rp::json_obj type "$(rp::json_str QUEUE_DELAY)" queueDelay "$2" ;;
  REQUEST_COUNT) rp::json_obj type "$(rp::json_str REQUEST_COUNT)" requestCount "$2" ;;
  *) rp::usage "unknown scaler type: '$1' (expected QUEUE_DELAY|REQUEST_COUNT)" ;;
  esac
}

# Pod network-volume mount: [{volumeId, path}]. path defaults to /workspace for
# back-compat (the spec says network-mount path has no default — pass $2 to set it
# explicitly).
rp::json_nv_mount() {
  jq -nc --arg v "$1" --arg p "${2:-$RP_DEFAULT_MOUNT_PATH}" '[{volumeId:$v, path:$p}]'
}

# Persistent container mount: {persistent:{size, path}}. path defaults to
# /workspace (overridable via $2; the spec allows changing it via PATCH).
rp::json_persistent_mount() {
  rp::json_obj persistent "$(rp::json_obj size "$1" path "$(rp::json_str "${2:-$RP_DEFAULT_MOUNT_PATH}")")"
}
