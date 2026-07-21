#!/usr/bin/env bash
# `rp registry` — container-registry auth CRUD (REST).

_registry_list() {
  local body
  body="$(rp::http GET /containerregistryauth)"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  rp::table "$body" id name
}

_registry_get() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp registry get <id>"
  local body
  body="$(rp::http GET "/containerregistryauth/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s\n' "$body" | jq .
}

_registry_create() {
  local name server username password
  name="$(rp::args_get name)"
  server="$(rp::args_get server)"
  username="$(rp::args_get username)"
  password="$(rp::args_get password)"
  [[ -n "$name" && -n "$server" && -n "$username" ]] || rp::usage "usage: rp registry create --name <n> --server <url> --username <u> [--password <p> (prefer interactive prompt)]"
  if [[ -z "$password" ]]; then
    IFS= read -rs -p "Password: " password </dev/tty || true
    echo >&2
    [[ -n "$password" ]] || rp::usage "no password entered"
  else
    rp::warn "note: --password is visible in process listings and shell history; prefer the interactive prompt"
  fi
  local body res newid
  body="$(rp::json_obj name "$(rp::json_str "$name")" server "$(rp::json_str "$server")" username "$(rp::json_str "$username")" password "$(rp::json_str "$password")")"
  res="$(rp::http POST /containerregistryauth "$body")"
  newid="$(printf '%s' "$res" | jq -r '.id')"
  rp::ok "created registry auth: $newid"
  printf '%s\n' "$newid"
}

_registry_delete() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp registry delete <id>"
  rp::http DELETE "/containerregistryauth/$id" >/dev/null
  rp::ok "deleted registry auth $id"
}

rp::cmd_registry() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) _registry_list ;;
  get) _registry_get ;;
  create) _registry_create ;;
  delete) _registry_delete ;;
  -h | --help | help)
    echo "Usage: rp registry <create|list|get|delete>"
    ;;
  *) rp::usage "unknown registry verb: '$verb'" ;;
  esac
}
