#!/usr/bin/env bash
#
# Pod ssh connection line; key management moved to rp ssh-key.
#
# `info` prints the ssh connection line for a running pod. The three key verbs
# (list-keys / add-key / remove-key) are DEPRECATED aliases onto the v2 REST
# `rp ssh-key` Resource: this file sources commands/ssh-key.sh and calls its
# _sshkey_* functions, warning and delegating so the key logic lives in exactly
# one place. There is no GraphQL path — both surfaces hit
# GET/PUT /v2/account/ssh-keys. Use `rp ssh-key` for keys; `rp ssh` is now just
# `info`.
#
# Usage: rp ssh <verb> [flags]
#

# Only one command module is sourced per invocation, so pull in the canonical
# key implementation explicitly; the aliases below call its _sshkey_* functions.
. "$RP_ROOT/commands/ssh-key.sh"

_ssh_info_human() {
  local user="${2:-root}"
  printf '%s' "$1" | jq -r --arg user "$user" '
    . as $p
    | ($p.runtime.ports // []) as $ports
    | ($ports | map(select((.type // "") == "tcp" or (.type // "") == "ssh"))) as $ssh
    | if ($ssh | length) > 0
      then "ssh \($user)@\($ssh[0].ip) -p \($ssh[0].public)"
      elif $p.runtime == null then "pod has no runtime (stopped?)"
      else "no ssh port labelled; runtime ports: \($ports | map({ip, public, type}))"
      end'
}

_ssh_info() {
  local id user
  rp::require_pos id "usage: rp ssh info <pod-id>"
  user="$(rp::args_get user root)"
  local body
  body="$(rp::http GET "/pods/$id")"
  rp::emit_json_or "$body" _ssh_info_human "$body" "$user"
}

###
### :::: documentation (rp doc ssh) :::: ######################################
###

# doc: list-keys
# List your registered public keys.
#
# DEPRECATED — use `rp ssh-key list`.
#
# Usage: rp ssh list-keys [--json]
#
# Options:
#   --json  print the keys as a JSON array of authorized-key lines
#
# Notes:
#   DEPRECATED: this verb now warns and delegates to `rp ssh-key list`, which is
#   the canonical key command — same v2 REST route, same output. Prefer
#   `rp ssh-key list` in new scripts. The table shows the key type, its SHA256
#   fingerprint, and the first 64 characters of the key itself. Fingerprints are
#   computed locally by ssh-keygen; where ssh-keygen is absent the column reads -
#   and fingerprint matching stops working. Every key lives in the v2 account key
#   set; the CLI splits it into one key per line.
#
# API: GET /v2/account/ssh-keys

# doc: add-key
# Add a public key from a file or stdin.
#
# DEPRECATED — use `rp ssh-key add`.
#
# Usage: rp ssh add-key <file|->
#
# Arguments:
#   <file|->  public-key file to read; - or no argument reads stdin
#
# Notes:
#   DEPRECATED: this verb now warns and delegates to `rp ssh-key add`, the
#   canonical key command (same v2 REST route). Only the first non-blank line of
#   the input is registered, so pointing this at an authorized_keys file with
#   several keys adds just the first. Re-adding a key you already hold is a no-op.
#   The write is read-modify-write over the v2 key set — the whole set is fetched,
#   appended to, and sent back as a JSON array — so two adds racing from different
#   sessions are serialised behind a lock. --json is accepted and ignored: the
#   outcome is a status line on stderr.
#
# Examples:
#   rp ssh-key add ~/.ssh/id_ed25519.pub
#   ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -
#
# API: PUT /v2/account/ssh-keys

# doc: remove-key
# Remove a registered public key.
#
# DEPRECATED — use `rp ssh-key remove`.
#
# Usage: rp ssh remove-key <fingerprint|key>
#
# Arguments:
#   <fingerprint|key>  SHA256 fingerprint from `rp ssh-key list`, or any
#                      substring of the key line
#
# Notes:
#   DEPRECATED: this verb now warns and delegates to `rp ssh-key remove`, the
#   canonical key command (same v2 REST route). Exactly one key must match: a
#   fingerprint is compared whole and anything else as a substring, so a fragment
#   hitting several keys is rejected rather than removing them all. No match is a
#   not-found error and nothing is written. The surviving keys are rewritten as a
#   JSON array, so the same read-modify-write race as `rp ssh add-key` applies.
#   --json is accepted and ignored.
#
# Examples:
#   rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
#   rp ssh-key remove laptop@example.com
#
# API: PUT /v2/account/ssh-keys

# doc: info
# Print the ssh connection line for a running pod.
#
# Usage: rp ssh info <pod-id> [--json] [--user <u>]
#
# Arguments:
#   <pod-id>  pod id — from `rp pod list`
#
# Options:
#   --json    print the raw pod record the line was derived from
#   --user <u>  remote login user in the connection line (default: root)
#
# Notes:
#   This is the one verb here that never touches the key set: it reads the pod
#   over REST API v2 and formats what it finds, so it keeps working even where
#   the key verbs would not. The line comes from the first runtime port labelled
#   ssh, or failing that the first TCP port. The login user defaults to `root`
#   (Runpod official images run as root), but images that run as a non-root user
#   need `--user` set to match, otherwise the printed `ssh` line fails with a
#   permission error. The --user value is not validated against the pod — the CLI
#   has no API field for a container's default user — so pass the user the image
#   actually starts as. A stopped pod has no runtime and so no connection line —
#   the command says as much rather than failing. Start the pod and ask again. A
#   running pod exposing no ssh or TCP port prints its runtime ports instead.
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
  list-keys)
    rp::warn "rp ssh list-keys is deprecated; use 'rp ssh-key list'"
    _sshkey_list
    ;;
  add-key)
    rp::warn "rp ssh add-key is deprecated; use 'rp ssh-key add'"
    _sshkey_add
    ;;
  remove-key)
    rp::warn "rp ssh remove-key is deprecated; use 'rp ssh-key remove'"
    _sshkey_remove
    ;;
  info) _ssh_info ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp ssh <verb>   (key verbs deprecated — use rp ssh-key; ssh is now just info)
  list-keys                     [deprecated] list keys — use: rp ssh-key list
  add-key <file|->              [deprecated] add a key  — use: rp ssh-key add
  remove-key <fingerprint|key>  [deprecated] remove a key — use: rp ssh-key remove
  info <pod-id> [--user <u>]    ssh connection line for a running pod (default user: root)
EOF
    ;;
  *) rp::usage "unknown ssh verb: '$verb'" ;;
  esac
}
