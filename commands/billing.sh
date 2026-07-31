#!/usr/bin/env bash
#
# `rp billing` — pod / serverless / public-endpoint / cluster / network-volume
# billing (REST API v2).
# Usage: rp billing <verb> [flags]
#
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
  serverless)
    # v2's only billing filter: serverlessId on /billing/serverless.
    local sid
    sid="$(rp::args_pos)"
    _billing "/billing/serverless${sid:+?serverlessId=$sid}"
    ;;
  public-endpoints) _billing /billing/endpoints ;;
  clusters) _billing /billing/clusters ;;
  volumes) _billing /billing/networkvolumes ;;
  all) _billing /billing ;;
  endpoints)
    rp::warn "'rp billing endpoints' is deprecated — use 'rp billing serverless' (serverless spend) or 'rp billing public-endpoints' (public-endpoint product)"
    _billing /billing/serverless
    ;;
  -h | --help | help)
    echo "Usage: rp billing <pods|serverless [id]|public-endpoints|clusters|volumes|all>"
    ;;
  *) rp::usage "unknown billing verb: '$verb'" ;;
  esac
}
