#!/usr/bin/env bash
# jq-backed JSON builders (string / array / object / merge) used to assemble REST request bodies.
[[ -n "${_RP_JSON:-}" ]] && return 0
_RP_JSON=1

_json_merge() { jq -c -n --argjson a "$1" --argjson b "$2" '$a * $b'; }

rp::json_str() { jq -Rc . <<<"$1"; }

rp::json_array() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@" | jq -R . | jq -sc .
  else
    printf '[]'
  fi
}

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
