#!/usr/bin/env bash
# SSH-key group. Keys are stored as a newline-joined string on `myself.pubKey`
# (read) and written via the `updateUserSettings(input:{pubKey})` mutation — both
# confirmed against runpodctl's api/user.go. `info` derives the ssh line from a
# pod's runtime ports.

_ssh_pubkey_raw() {
  rp::graphql 'query { myself { pubKey } }' | jq -r '.myself.pubKey // ""'
}

_ssh_write_pubkey() {
  local keys="$1"
  local q='mutation($input:UpdateUserSettingsInput){ updateUserSettings(input:$input){ id } }'
  local vars
  vars="$(jq -c -n --arg k "$keys" '{input:{pubKey:$k}}')"
  rp::graphql "$q" "$vars" >/dev/null
}

# stdin: one authorized-key line -> its SHA256 fingerprint (empty if ssh-keygen missing)
_ssh_fp() {
  command -v ssh-keygen >/dev/null 2>&1 || return 0
  ssh-keygen -lf - 2>/dev/null | awk '{print $2}'
}

_ssh_list_keys() {
  local raw
  raw="$(_ssh_pubkey_raw)"
  if rp::args_has json; then
    printf '%s\n' "$(printf '%s' "$raw" | jq -R -s 'split("\n")|map(select(length>0))')"
    return
  fi
  printf '%s\t%s\t%s\n' "TYPE" "FINGERPRINT" "KEY"
  local fp line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_ssh_fp <<<"$line")"
    printf '%s\t%s\t%s\n' "${line%% *}" "${fp:--}" "${line:0:64}"
  done <<<"$raw"
}

_ssh_add_key() {
  local src newkey
  src="$(rp::args_pos)"
  if [[ -z "$src" || "$src" == "-" ]]; then
    newkey="$(cat)"
  else
    [[ -r "$src" ]] || rp::notfound "cannot read key file: $src"
    newkey="$(<"$src")"
  fi
  newkey="$(printf '%s' "$newkey" | awk 'NF' | head -n1)"
  [[ -n "$newkey" ]] || rp::usage "no key found in input"
  local raw kept="" found=0 line
  raw="$(_ssh_pubkey_raw)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == "$newkey" ]] && found=1
    kept="${kept:+$kept$'\n'}$line"
  done <<<"$raw"
  if [[ "$found" == 1 ]]; then
    rp::ok "key already registered"
    return 0
  fi
  _ssh_write_pubkey "${kept:+$kept$'\n'}$newkey"
  rp::ok "added key"
}

_ssh_remove_key() {
  local target
  target="$(rp::args_pos)"
  [[ -n "$target" ]] || rp::usage "usage: rp ssh remove-key <fingerprint|key>"
  local raw kept="" line fp matches=0
  raw="$(_ssh_pubkey_raw)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_ssh_fp <<<"$line")"
    if [[ "$fp" == "$target" || "$line" == *"$target"* ]]; then
      matches=$((matches + 1))
    else
      kept="${kept:+$kept$'\n'}$line"
    fi
  done <<<"$raw"
  # Refuse to bulk-remove: a short substring can match several keys, so require
  # exactly one hit and ask for a more specific fingerprint/key otherwise.
  ((matches)) || rp::notfound "no matching key found for '$target'"
  ((matches == 1)) || rp::usage "ambiguous: '$target' matches $matches keys; use a longer fingerprint or key substring"
  _ssh_write_pubkey "$kept"
  rp::ok "removed key"
}

_ssh_info() {
  local id
  id="$(rp::args_pos)"
  [[ -n "$id" ]] || rp::usage "usage: rp ssh info <pod-id>"
  local body
  body="$(rp::http GET "/pods/$id")"
  if rp::args_has json; then
    printf '%s\n' "$body"
    return
  fi
  printf '%s' "$body" | jq -r '
    . as $p
    | ($p.runtime.ports // []) as $ports
    | ($ports | map(select(.label == "ssh" or (.portType // .type // "") == "tcp"))) as $ssh
    | if ($ssh | length) > 0
      then "ssh root@\($ssh[0].ip) -p \($ssh[0].publicPort)"
      elif $p.runtime == null then "pod has no runtime (stopped?)"
      else "no ssh port labelled; runtime ports: \($ports | map({ip, publicPort, label}))"
      end'
}

rp::cmd_ssh() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list-keys) _ssh_list_keys ;;
  add-key) _ssh_add_key ;;
  remove-key) _ssh_remove_key ;;
  info) _ssh_info ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp ssh <verb>
  list-keys                     list your registered public keys (GraphQL myself.pubKey)
  add-key <file|->              add a public key (file path, or - / stdin)
  remove-key <fingerprint|key>  remove a key by SHA256 fingerprint or key substring
  info <pod-id>                 ssh connection line for a running pod
EOF
    ;;
  *) rp::usage "unknown ssh verb: '$verb'" ;;
  esac
}
