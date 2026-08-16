#!/usr/bin/env bash
#
# SSH public keys, and the ssh line for a running pod.
#
# Your keys live on your account as one newline-joined string, which the three
# key verbs read and rewrite over GraphQL — API v2 has no user-settings path.
# `info` is the exception: it reads a pod's runtime ports over REST and prints
# the command that reaches it.
#
# Usage: rp ssh <verb> [flags]
#

# Keys are stored as a newline-joined string on `myself.pubKey` (read) and
# written via the `updateUserSettings(input:{pubKey})` mutation — both confirmed
# against runpodctl's api/user.go.
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

# Serialise concurrent read-modify-write of `myself.pubKey` so two `rp ssh
# add-key` / `remove-key` from the same host cannot clobber each other (lost
# update): each fetches the whole set, mutates it, and writes it back, so a pair
# racing leaves one edit lost. A mkdir(1)-based lock is created atomically, so
# only one process holds it; others spin briefly then proceed. No flock needed,
# so it works on Bash 3.2 / macOS / Linux. $1 is the callback to run while
# holding the lock; the rest are its args. A stale lock left by a crashed/killed
# holder is reclaimed by checking the recorded PID.
_ssh_locked() {
  local fn="$1"
  shift
  local lock_dir="${TMPDIR:-/tmp}/.rp-ssh-pubkey.lock"
  local tries=0 pid
  while ! mkdir "$lock_dir" 2>/dev/null; do
    pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    tries=$((tries + 1))
    ((tries > 50)) && rp::die "could not acquire the ssh key lock (another rp ssh add-key/remove-key is running)"
    sleep 0.1
  done
  printf '%s' "$$" >"$lock_dir/pid" 2>/dev/null
  "$fn" "$@"
  local rc=$?
  rm -f "$lock_dir/pid" 2>/dev/null
  rmdir "$lock_dir" 2>/dev/null
  return "$rc"
}

# stdin: one authorized-key line -> its SHA256 fingerprint (empty if ssh-keygen missing)
_ssh_fp() {
  command -v ssh-keygen >/dev/null 2>&1 || return 0
  ssh-keygen -lf - 2>/dev/null | awk '{print $2}'
}

_ssh_list_keys_human() {
  printf '%s\t%s\t%s\n' "TYPE" "FINGERPRINT" "KEY"
  local fp line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_ssh_fp <<<"$line")"
    printf '%s\t%s\t%s\n' "${line%% *}" "${fp:--}" "${line:0:64}"
  done <<<"$1"
}

_ssh_list_keys() {
  local raw keys_json
  raw="$(_ssh_pubkey_raw)"
  keys_json="$(printf '%s' "$raw" | jq -R -s 'split("\n")|map(select(length>0))')"
  rp::emit_json_or "$keys_json" _ssh_list_keys_human "$raw"
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
  rp::require_pos target "usage: rp ssh remove-key <fingerprint|key>"
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
  ((matches == 1)) || rp::usage "usage: rp ssh remove-key '$target' is ambiguous ($matches keys match); use a longer fingerprint or key substring"
  _ssh_write_pubkey "$kept"
  rp::ok "removed key"
}

_ssh_info_human() {
  printf '%s' "$1" | jq -r '
    . as $p
    | ($p.runtime.ports // []) as $ports
    | ($ports | map(select((.type // "") == "tcp" or (.type // "") == "ssh"))) as $ssh
    | if ($ssh | length) > 0
      then "ssh root@\($ssh[0].ip) -p \($ssh[0].public)"
      elif $p.runtime == null then "pod has no runtime (stopped?)"
      else "no ssh port labelled; runtime ports: \($ports | map({ip, public, type}))"
      end'
}

_ssh_info() {
  local id
  rp::require_pos id "usage: rp ssh info <pod-id>"
  local body
  body="$(rp::http GET "/pods/$id")"
  rp::emit_json_or "$body" _ssh_info_human "$body"
}

###
### :::: documentation (rp doc ssh) :::: ######################################
###

# doc: list-keys
# List your registered public keys.
#
# Usage: rp ssh list-keys [--json]
#
# Options:
#   --json  print the keys as a JSON array of authorized-key lines
#
# Notes:
#   The table shows the key type, its SHA256 fingerprint, and the first 64
#   characters of the key itself.
#   Fingerprints are computed locally by ssh-keygen. Where ssh-keygen is not
#   installed the column reads - and matching by fingerprint stops working.
#   Every key lives in a single newline-joined pubKey string on your user
#   record; the CLI splits it back into one key per line.
#
# API: GraphQL myself { pubKey }  (NO-V2-EQUIVALENT)

# doc: add-key
# Add a public key from a file or stdin.
#
# Usage: rp ssh add-key <file|->
#
# Arguments:
#   <file|->  public-key file to read; - or no argument reads stdin
#
# Notes:
#   Only the first non-blank line of the input is registered, so pointing this
#   at an authorized_keys file with several keys adds just the first.
#   Re-adding a key you already hold is a no-op: the CLI says so and writes
#   nothing.
#   The write is read-modify-write over one joined string — the whole set is
#   fetched, appended to, and sent back — so two adds racing from different
#   sessions can lose one of the keys.
#   --json is accepted and ignored: the outcome is a status line on stderr.
#
# Examples:
#   rp ssh add-key ~/.ssh/id_ed25519.pub
#   ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh add-key -
#
# API: GraphQL updateUserSettings(input: { pubKey })  (NO-V2-EQUIVALENT)

# doc: remove-key
# Remove a registered public key.
#
# Usage: rp ssh remove-key <fingerprint|key>
#
# Arguments:
#   <fingerprint|key>  SHA256 fingerprint from `rp ssh list-keys`, or any
#                      substring of the key line
#
# Notes:
#   Exactly one key must match. A fingerprint is compared whole and anything
#   else as a substring, so a fragment that hits several keys is rejected
#   rather than removing them all — pass a longer fingerprint or key fragment.
#   No match at all is a not-found error and nothing is written.
#   The surviving keys are rewritten as one joined string, so the same
#   read-modify-write race as `rp ssh add-key` applies.
#   --json is accepted and ignored: the outcome is a status line on stderr.
#
# Examples:
#   rp ssh remove-key SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
#   rp ssh remove-key laptop@example.com
#
# API: GraphQL updateUserSettings(input: { pubKey })  (NO-V2-EQUIVALENT)

# doc: info
# Print the ssh connection line for a running pod.
#
# Usage: rp ssh info <pod-id> [--json]
#
# Arguments:
#   <pod-id>  pod id — from `rp pod list`
#
# Options:
#   --json    print the raw pod record the line was derived from
#
# Notes:
#   This is the one verb here that never touches GraphQL: it reads the pod over
#   REST API v2 and formats what it finds, so it keeps working even where the
#   key verbs would not.
#   The line comes from the first runtime port labelled ssh, or failing that
#   the first TCP port, printed as `ssh root@<ip> -p <port>`.
#   A stopped pod has no runtime and so no connection line — the command says
#   as much rather than failing. Start the pod and ask again.
#   A running pod exposing no ssh or TCP port prints its runtime ports instead,
#   so you can see what it does expose.
#   Registering a key with `rp ssh add-key` is what makes the address usable;
#   this verb only reports it.
#
# API: GET /v2/pods/{id}

rp::cmd_ssh() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list-keys) _ssh_list_keys ;;
  add-key) _ssh_locked _ssh_add_key ;;
  remove-key) _ssh_locked _ssh_remove_key ;;
  info) _ssh_info ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp ssh <verb>   (keys via GraphQL — no API v2 endpoint yet)
  list-keys                     list your registered public keys (myself.pubKey)
  add-key <file|->              add a public key (file path, or - / stdin)
  remove-key <fingerprint|key>  remove a key by SHA256 fingerprint or key substring
  info <pod-id>                 ssh connection line for a running pod
EOF
    ;;
  *) rp::usage "unknown ssh verb: '$verb'" ;;
  esac
}
