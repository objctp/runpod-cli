#!/usr/bin/env bash
# `rp billing` — pod / endpoint / network-volume billing (REST).

_billing() {
  local body
  body="$(rp::http GET "$1")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

rp::cmd_billing() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  pods) _billing /billing/pods ;;
  endpoints) _billing /billing/endpoints ;;
  volumes) _billing /billing/networkvolumes ;;
  -h | --help | help)
    echo "Usage: rp billing <pods|endpoints|volumes>"
    ;;
  *) rp::usage "unknown billing verb: '$verb'" ;;
  esac
}
