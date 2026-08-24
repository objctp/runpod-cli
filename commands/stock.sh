#!/usr/bin/env bash
#
# Catalogue of GPU types, CPU flavours, and datacentres.
#
# Read-only lookups against the API v2 catalogue: what hardware exists, what it
# costs, and where it is in stock right now. The ids printed here are the ones
# `rp pod create` takes for --gpu, --cpu-flavor and --dc. Every column is v2
# REST bar the S3-API column of `rp stock dc`, which has no v2 field and stays
# on GraphQL.
#
# Usage: rp stock <verb> [flags]
#

_stock_gpu() {
  local product cloud cuda count q data
  product="$(rp::args_get product "$RP_DEFAULT_PRODUCT")"
  product="${product^^}"
  cloud="$(rp::args_get cloud)"
  cloud="${cloud^^}"
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
  [[ -z "$count" || "$count" -ge "$RP_STOCK_COUNT_MIN" ]] || rp::usage "--min-count must be >= $RP_STOCK_COUNT_MIN (got $count)"
  q="$(rp::query_params include AVAILABILITY product "$product" cloud "$cloud" minCudaVersion "$cuda" count "$count")"
  data="$(rp::http GET "/catalog/gpus$q" | rp::unwrap gpus)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, DISPLAY:.name, VRAM_GB:(.memory//0), SECURE_PRICE:(.price.secure//""), STOCK:(.availability//"")})' \
    ID DISPLAY VRAM_GB SECURE_PRICE STOCK
}

_stock_cpus() {
  local data dc
  data="$(rp::http GET "/catalog/cpus$(rp::query_params include AVAILABILITY product "$RP_DEFAULT_PRODUCT")" | rp::unwrap cpus)"
  dc="$(rp::args_get dc)"
  if [[ -n "$dc" ]]; then
    data="$(printf '%s' "$data" | jq -c --arg dc "${dc^^}" 'map(select(([.dataCenters // [] | .[].id | ascii_upcase] | index($dc))))')"
  fi
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, NAME:.name, GROUP:.group, VCPU:((.vcpu.min|tostring)+"-"+(.vcpu.max|tostring)), RAM_GB_VCPU:(.ramGbPerVcpu//""), SECURE_PRICE_VCPU:(.price.securePerVcpu//""), STOCK:(.availability//""), DATACENTERS:((.dataCenters // [] | map(.id) | sort) as $dcs | if ($dcs | length) <= 2 then ($dcs | join(", ")) else (($dcs[0:2] | join(", ")) + " +" + (($dcs | length) - 2 | tostring) + " more") end)})' \
    ID NAME GROUP VCPU RAM_GB_VCPU SECURE_PRICE_VCPU STOCK DATACENTERS
}

_stock_dc() {
  local dcs s3set filt shaped
  dcs="$(rp::http GET '/catalog/datacenters?include=GPU_AVAILABILITY,CPU_AVAILABILITY' | rp::unwrap dataCenters)"
  s3set="$(printf '%s\n' "$(_s3_dcs)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"

  # Filter flags. --s3 / --global-network are bare bools; --volume-type and
  # --compliance are comma-separated allow-lists (keep a DC if it carries at least
  # one listed item, case-insensitive). The SAME filtered set feeds both the
  # --json payload and the reshaped table, so the two views never diverge.
  local s3f globalf vols comps
  s3f="$(rp::args_has s3 && printf true || printf false)"
  globalf="$(rp::args_has global-network && printf true || printf false)"
  vols="$(rp::split_csv "$(rp::args_get volume-type)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"
  comps="$(rp::split_csv "$(rp::args_get compliance)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"

  filt="$(printf '%s' "$dcs" | jq -c \
    --argjson s3 "$s3set" --argjson s3f "$s3f" --argjson globalf "$globalf" \
    --argjson vols "$vols" --argjson comps "$comps" '
    map(select(
      (.id | ascii_upcase) as $dc |
      (($s3f | not) or ($s3 | index($dc))) and
      (($globalf | not) or .globalNetwork) and
      (($vols | length) == 0 or ((.networkVolumeTypes // []) | map(ascii_upcase) | any(. as $t | $vols | index($t)))) and
      (($comps | length) == 0 or ((.compliance // []) | map(ascii_upcase) | any(. as $t | $comps | index($t))))
    ))')"

  # rp::table takes no jq args, so pre-shape (joining the S3 set) then table it.
  shaped="$(printf '%s' "$filt" | jq -c --argjson s3 "$s3set" '
    map((.id | ascii_upcase) as $dc | {
      DATACENTER:    .id,
      REGION:        .region,
      GLOBAL_NETWORK: (if .globalNetwork then "yes" else "" end),
      COMPLIANCE:    ((.compliance // []) | join(", ")),
      NETWORK_VOLUME_TYPES: ((.networkVolumeTypes // []) | join(", ")),
      GPUS:          ((.gpuAvailability // []) | map(select(.availability != "NONE")) | length),
      S3_API:        (if ($s3 | index($dc)) then "yes" else "" end)
    }) | sort_by(.DATACENTER)')"
  rp::emit_json_or "$filt" rp::table "$shaped" DATACENTER REGION GPUS S3_API GLOBAL_NETWORK COMPLIANCE NETWORK_VOLUME_TYPES
}

###
### :::: documentation (rp doc stock) :::: ####################################
###

# doc: gpu
# List GPU types with price and live availability.
#
# Usage: rp stock gpu [--product <p,…>] [--min-count N]
#                     [--cloud SECURE|COMMUNITY] [--min-cuda <ver>] [--json]
#
# Options:
#   --product <p,…>           POD, CLUSTER or SERVERLESS, comma-separated
#                             (default: POD,SERVERLESS)
#   --min-count N             only types with at least N GPUs free on one host
#                             (minimum 1)
#   --cloud SECURE|COMMUNITY  hardware tier; omit for both
#   --min-cuda <ver>          minimum CUDA version, major or major.minor
#   --json                    print the raw API response
#
# Notes:
#   The ID column is the value `rp pod create --gpu` and
#   `rp serverless create --gpu` take. Ids are display names containing
#   spaces, so quote them.
#   STOCK is availability for the product and cloud you asked about, so one
#   card can read differently under --product POD and --product SERVERLESS.
#   SECURE_PRICE is the secure-cloud rate per GPU per hour; community pricing
#   is not in this table.
#   --min-count is per host: it asks for N of that GPU in one machine, not N
#   across the fleet. The floor is 1, so 0 or a negative is a usage error.
#   --min-cuda takes 12 or 12.1; any other shape is rejected before the call.
#
# Examples:
# # Show secure-cloud GPUs with at least two in stock
# $ rp stock gpu --cloud SECURE --min-count 2
# # Show serverless GPUs with CUDA 12.4 or newer
# $ rp stock gpu --product SERVERLESS --min-cuda 12.4
#
# API: GET /v2/catalog/gpus  (include=AVAILABILITY)

# doc: cpus
# List CPU flavours with price and availability.
#
# Usage: rp stock cpus [--dc <id>] [--json]
#
# Options:
#   --dc <id>   keep only flavours stocked in this datacentre (case-insensitive)
#   --json      print the raw API response
#
# Notes:
#   The ID column is the value `rp pod create --cpu-flavor` takes.
#   VCPU is the flavour's valid vcpuCount range; --vcpu must be a power of two
#   inside it.
#   RAM_GB_VCPU is the RAM allotted per vCPU and SECURE_PRICE_VCPU the
#   secure-cloud hourly rate per vCPU, so both scale with the vCPU count you
#   ask for.
#   This verb takes one optional filter and no others: --dc <id> keeps only
#   the flavours stocked in that datacentre (case-insensitive). The filter
#   applies to BOTH the table and --json, so the two views always show the
#   same flavours.
#   DATACENTERS lists every datacentre the flavour is stocked in, but the
#   table column is truncated to the first two ids followed by "+N more"
#   (e.g. "EU-CZ-1, EU-NL-1 +12 more") to keep the row readable; the full
#   list is always in --json. Because filtering matches the underlying
#   dataCenters array, --dc still finds a flavour even when its datacentre
#   is hidden behind "+N more".
#   This verb takes no other filters: the product is fixed at POD,SERVERLESS.
#
# API: GET /v2/catalog/cpus  (include=AVAILABILITY, product=POD,SERVERLESS)

# doc: dc
# List datacentres with GPU stock and S3-API support.
#
# Usage: rp stock dc [--json] [--s3] [--global-network] [--volume-type <t,…>]
#                     [--compliance <c,…>]
#
# Options:
#   --json          print the raw v2 datacentre records (post-filter)
#   --s3            keep only S3-API-enabled datacentres
#   --global-network  keep only datacentres on Runpod's global network
#   --volume-type <t,…>  keep only datacentres supporting at least one listed
#                        network-volume tier (e.g. STANDARD,HIGH_PERFORMANCE)
#   --compliance <c,…>   keep only datacentres carrying at least one listed
#                        certification (e.g. SOC_2_TYPE_2)
#
# Notes:
#   Filters combine as a logical AND; within a comma list they are OR. All flags
#   apply to BOTH the table and --json, so the two views always show the same
#   datacentres (--json omits the S3_API column, which is a CLI-side join).
#   The DATACENTER column is the id `rp pod create --dc` and
#   `rp volume create --dc` take. (The v2 `name` field is the same value in
#   practice and is not shown as a separate column.)
#   GPUS counts how many GPU types have any stock there, not how many cards
#   are free.
#   GLOBAL_NETWORK marks datacentres that support global networking — Runpod's
#   private, cross-datacenter pod-to-pod network (pods reach each other over
#   *.runpod.internal without opening ports to the public internet). It is
#   unrelated to the S3_API column.
#   COMPLIANCE lists the certifications the datacentre carries (e.g.
#   SOC_2_TYPE_2), comma-separated; blank where none are advertised.
#   NETWORK_VOLUME_TYPES lists the network-volume tiers the datacentre supports
#   (e.g. STANDARD, HIGH_PERFORMANCE), comma-separated; blank where none are
#   advertised. The tier constrains the kind of volume `rp volume create` can
#   place there.
#   S3_API marks the datacentres whose network volumes expose the
#   S3-compatible API — the ones `rp volume sync` can reach.
#   That column is NO-V2-EQUIVALENT: v2 carries no S3 field anywhere, so it is
#   joined in from the GraphQL dataCenters query — the same resolver
#   `rp volume create` guards on — with an offline snapshot behind it. The
#   column therefore stays live where GraphQL is reachable and still renders
#   when it is not.
#   --json prints the v2 datacentre records alone: S3_API is a CLI-side join
#   and is absent from that payload.
#
# Examples:
# # Datacentres that are BOTH S3-API enabled AND on the global network
# $ rp stock dc --s3 --global-network
# # Datacentres that support the HIGH_PERFORMANCE volume tier
# $ rp stock dc --volume-type HIGH_PERFORMANCE
#
# API: GET /v2/catalog/datacenters  (include=GPU_AVAILABILITY,CPU_AVAILABILITY)

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
    echo "Usage: rp stock gpu [--product POD,CLUSTER,SERVERLESS] [--min-count N] [--cloud SECURE|COMMUNITY] [--min-cuda <ver>] | rp stock cpus [--dc <id>] | rp stock dc [--json] [--s3] [--global-network] [--volume-type <t,…>] [--compliance <c,…>]   (dc list via v2; filters apply to both table and --json)"
    ;;
  *) rp::usage "unknown stock verb: '$verb'" ;;
  esac
}
