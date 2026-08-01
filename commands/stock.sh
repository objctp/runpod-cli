#!/usr/bin/env bash
#
# `rp stock` — GPU types, CPU flavours, and datacentres.
# Usage: rp stock <verb> [flags]
#
# `gpu`, `cpus`, and the DC *list* use REST API v2 (catalog/gpus, catalog/cpus,
# catalog/datacenters with per-DC stock); the DC *S3 column* stays GraphQL (v2
# has no s3apiEnabled field), sourced via lib/validate.sh's `_s3_dcs` with an
# offline fallback.

# rp stock gpu — GPU types (v2) with availability + optional filters.
# GET /v2/catalog/gpus (listGpuTypes, include=AVAILABILITY). Filters compose onto
# the query: --product (POD|CLUSTER|SERVERLESS, csv; default POD,SERVERLESS),
# --min-count N (count), --cloud SECURE|COMMUNITY, --min-cuda <ver> (minCudaVersion).
_stock_gpu() {
  local product cloud cuda count q data
  product="$(rp::args_get product POD,SERVERLESS)"
  cloud="$(rp::args_get cloud)"
  case "$cloud" in '' | SECURE | COMMUNITY) ;; *) rp::usage "invalid --cloud '$cloud' (expected SECURE|COMMUNITY)" ;; esac
  cuda="$(rp::args_get min-cuda)"
  [[ -z "$cuda" || "$cuda" =~ ^[0-9]+(\.[0-9]+)?$ ]] || rp::usage "invalid --min-cuda '$cuda' (expected major or major.minor, e.g. 12 or 12.1)"
  # Read raw and validate directly — not via rp::args_get_uint, which wraps
  # rp::require_uint inside $() and so swallows the usage exit when errexit is
  # off in tests. The direct call lets a non-integer / negative --min-count fail
  # fast and stay testable (the -ge 1 floor below already runs direct for that
  # reason). Mirrors the rp::require_* nameref-family rule in lib/args.sh.
  count="$(rp::args_get min-count)"
  rp::require_uint "$count" min-count
  [[ -z "$count" || "$count" -ge 1 ]] || rp::usage "--min-count must be >= 1 (got $count)"
  q="include=AVAILABILITY&product=$product"
  [[ -z "$cloud" ]] || q+="&cloud=$cloud"
  [[ -z "$cuda" ]] || q+="&minCudaVersion=$cuda"
  [[ -z "$count" ]] || q+="&count=$count"
  data="$(rp::http GET "/catalog/gpus?$q" | rp::unwrap gpus)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, DISPLAY:.name, VRAM_GB:(.memory//0), SECURE_PRICE:(.price.secure//""), STOCK:(.availability//"")})' \
    ID DISPLAY VRAM_GB SECURE_PRICE STOCK
}

# rp stock cpus — CPU flavours (v2) with availability.
# GET /v2/catalog/cpus (listCpuTypes, include=AVAILABILITY&product=POD,SERVERLESS).
# The ID column is the value `rp pod create --cpu-flavor` takes; VCPU shows the
# valid vcpuCount range (power-of-two within it).
_stock_cpus() {
  local data
  data="$(rp::http GET '/catalog/cpus?include=AVAILABILITY&product=POD,SERVERLESS' | rp::unwrap cpus)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, NAME:.name, GROUP:.group, VCPU:((.vcpu.min|tostring)+"-"+(.vcpu.max|tostring)), RAM_GB_VCPU:(.ramGbPerVcpu//""), SECURE_PRICE_VCPU:(.price.securePerVcpu//""), STOCK:(.availability//"")})' \
    ID NAME GROUP VCPU RAM_GB_VCPU SECURE_PRICE_VCPU STOCK
}

# rp stock dc — datacentre list (v2) with per-DC GPU stock + the S3-API column.
# DC list + per-DC stock: GET /v2/catalog/datacenters (listDataCenters,
# include=GPU_AVAILABILITY,CPU_AVAILABILITY). The S3-API column has no v2 field
# (NO-V2-EQUIVALENT): it is sourced from lib/validate.sh's _s3_dcs — the same
# GraphQL-backed, offline-fallback resolver `rp volume create` guards on — so the
# column stays live where reachable and still renders when the API is down.
_stock_dc() {
  local dcs s3set shaped
  dcs="$(rp::http GET '/catalog/datacenters?include=GPU_AVAILABILITY,CPU_AVAILABILITY' | rp::unwrap dataCenters)"
  s3set="$(printf '%s\n' "$(_s3_dcs)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"
  # rp::table takes no jq args, so pre-shape (joining the S3 set) then table it.
  shaped="$(printf '%s' "$dcs" | jq -c --argjson s3 "$s3set" '
    map((.id | ascii_upcase) as $dc | {
      DATACENTER: .id,
      NAME:       .name,
      REGION:     .region,
      GPUS:       ((.gpuAvailability // []) | map(select(.availability != "NONE")) | length),
      S3_API:     (if ($s3 | index($dc)) then "yes" else "" end)
    }) | sort_by(.DATACENTER)')"
  rp::emit_json_or "$dcs" rp::table "$shaped" DATACENTER NAME REGION GPUS S3_API
}

rp::cmd_stock() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  gpu) _stock_gpu ;;
  cpus) _stock_cpus ;;
  dc) _stock_dc ;;
  -h | --help | help | "")
    echo "Usage: rp stock gpu [--product POD,CLUSTER,SERVERLESS] [--min-count N] [--cloud SECURE|COMMUNITY] [--min-cuda <ver>] | rp stock cpus | rp stock dc   (dc list via v2; S3 column via GraphQL + fallback)"
    ;;
  *) rp::usage "unknown stock verb: '$verb'" ;;
  esac
}
