#!/usr/bin/env bash
# `rp billing` — pod / serverless-endpoint / network-volume billing (REST API v2).
# v2 returns time-bucketed { records: [...], metadata }; both modes print it.
# Serverless spend lives at /billing/serverless (/billing/endpoints is the
# separate *public endpoint* product's billing).

_billing() {
  local body
  body="$(rp::http GET "$1")"
  rp::emit_json_or "$body" rp::json_pretty "$body"
}

rp::cmd_billing() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  pods) _billing /billing/pods ;;
  endpoints) _billing /billing/serverless ;;
  volumes) _billing /billing/networkvolumes ;;
  -h | --help | help)
    echo "Usage: rp billing <pods|endpoints|volumes>"
    ;;
  *) rp::usage "unknown billing verb: '$verb'" ;;
  esac
}
