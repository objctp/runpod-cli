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

# Parse newline-delimited K=V pairs (one per --env) into a JSON object. Each
# pair splits on the FIRST '=' only, so a value may itself contain '=' or ','
# (e.g. --env LIST=a,b -> {"LIST":"a,b"}). Blank lines are skipped.
rp::env_to_json() {
  local obj='{}' pair k v
  while IFS= read -r pair; do
    [[ -z "$pair" ]] && continue
    k="${pair%%=*}"
    v="${pair#*=}"
    obj="$(_json_merge "$obj" "$(rp::json_obj "$k" "$(rp::json_str "$v")")")"
  done <<<"$1"
  printf '%s' "$obj"
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

# Serverless GPU: {pools:[...], count}.
rp::json_gpu_endpoint() {
  rp::json_obj pools "$(rp::csv_to_jsonarray "$1")" count "$2"
}

# Worker scaling: {min, max}, omitting any empty field.
rp::json_workers() {
  local obj='{}'
  rp::obj_set obj min "$1"
  rp::obj_set obj max "$2"
  printf '%s' "$obj"
}

# Pod network-volume mount: [{volumeId, path:/workspace}].
rp::json_nv_mount() {
  jq -nc --arg v "$1" '[{volumeId:$v, path:"/workspace"}]'
}

# Persistent container mount: {persistent:{size, path:/workspace}}.
rp::json_persistent_mount() {
  rp::json_obj persistent "$(rp::json_obj size "$1" path "$(rp::json_str /workspace)")"
}
