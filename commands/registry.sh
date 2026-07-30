#!/usr/bin/env bash
#
# `rp registry` — container-registry auth CRUD (REST API v2).
# Usage: rp registry <verb> [flags]
#

_registry_create() {
  local name username password
  name="$(rp::args_get name)"
  username="$(rp::args_get username)"
  password="$(rp::args_get password)"
  [[ -n "$name" && -n "$username" ]] || rp::usage "usage: rp registry create --name <n> --username <u> [--password <p> (prefer interactive prompt)]"
  if [[ -z "$password" ]]; then
    IFS= read -rs -p "Password: " password </dev/tty || true
    echo >&2
    [[ -n "$password" ]] || rp::usage "no password entered"
  else
    rp::warn "note: --password is visible in process listings and shell history; prefer the interactive prompt"
  fi
  local body
  body="$(rp::json_obj name "$(rp::json_str "$name")" username "$(rp::json_str "$username")" password "$(rp::json_str "$password")")"
  rp::resource_create registry "" "$body"
}

rp::cmd_registry() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list registry id name ;;
  get) rp::resource_get registry ;;
  create) _registry_create ;;
  delete) rp::resource_delete registry ;;
  -h | --help | help)
    echo "Usage: rp registry <create|list|get|delete>"
    ;;
  *) rp::usage "unknown registry verb: '$verb'" ;;
  esac
}
