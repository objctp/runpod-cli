#!/usr/bin/env bash
# `rp stock` — GPU types and S3-enabled datacentres (GraphQL).

_stock_gpu() {
  local q='query { gpuTypes { id displayName memoryInGb maxGpuCount lowestPrice { minimumBidPrice uninterruptablePrice stockStatus } } }'
  local data
  data="$(rp::graphql "$q")"
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "ID" "DISPLAY" "VRAM_GB" "MIN_BID" "STOCK"
  printf '%s' "$data" | jq -r '.gpuTypes[] | [.id, .displayName, (.memoryInGb // 0), (.lowestPrice.minimumBidPrice // ""), (.lowestPrice.stockStatus // "")] | @tsv'
}

_stock_dc() {
  local data
  data="$(rp::graphql 'query { dataCenters { id name s3apiEnabled } }')"
  if rp::args_has json; then
    printf '%s\n' "$data"
    return
  fi
  printf '%s\t%s\n' "DATACENTER" "S3_API"
  printf '%s' "$data" | jq -r '.dataCenters[] | [.id, (if .s3apiEnabled then "yes" else "" end)] | @tsv' | sort
}

rp::cmd_stock() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  gpu) _stock_gpu ;;
  dc) _stock_dc ;;
  -h | --help | help | "")
    echo "Usage: rp stock gpu | rp stock dc"
    ;;
  *) rp::usage "unknown stock verb: '$verb'" ;;
  esac
}
