#!/usr/bin/env bash
#
# `rp stock` — GPU types and S3-enabled datacentres.
# Usage: rp stock <verb> [flags]
#
# `gpu` uses REST API v2 (catalog/gpus); `dc` stays on GraphQL (v2 has no
# s3apiEnabled equivalent — kept until RunPod exposes an S3-support field).

_stock_gpu() {
  local data
  data="$(rp::http GET '/catalog/gpus?include=AVAILABILITY&product=POD,SERVERLESS' | rp::unwrap gpus)"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, DISPLAY:.name, VRAM_GB:(.memory//0), SECURE_PRICE:(.price.secure//""), STOCK:(.availability//"")})' \
    ID DISPLAY VRAM_GB SECURE_PRICE STOCK
}

_stock_dc() {
  local data
  data="$(rp::graphql 'query { dataCenters { id name s3apiEnabled } }')"
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape '.dataCenters | map({DATACENTER:.id, S3_API:(if .s3apiEnabled then "yes" else "" end)}) | sort_by(.DATACENTER)' \
    DATACENTER S3_API
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
    echo "Usage: rp stock gpu | rp stock dc   (dc via GraphQL — v2 has no s3apiEnabled field)"
    ;;
  *) rp::usage "unknown stock verb: '$verb'" ;;
  esac
}
