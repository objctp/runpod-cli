#!/usr/bin/env bash
#
# SSH public keys over the API v2 REST plane.
#
# The canonical home for key management: `rp ssh list-keys` / `add-key` /
# `remove-key` are aliases that source this file and call the _sshkey_* functions
# below, so the key logic exists in exactly one place. The v2 route replaces the
# WHOLE key set on PUT, so add/remove are read-modify-write around a lock.
#
# Usage: rp ssh-key <verb> [flags]
#

# Serialise concurrent read-modify-write of the account key set so two
# `rp ssh-key add` / `remove` (or their `rp ssh add-key` / `remove-key` aliases)
# from the same host cannot clobber each other. A mkdir(1)-based lock works on
# Bash 3.2 / macOS / Linux without flock. $1 is the callback, the rest its args;
# a stale lock left by a crashed holder is reclaimed via its recorded PID.
_sshkey_locked() {
  local fn="$1"
  shift
  local lock_dir="${TMPDIR:-/tmp}/.rp-sshkey.lock"
  local tries=0 pid
  while ! mkdir "$lock_dir" 2>/dev/null; do
    pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lock_dir" 2>/dev/null
    fi
    tries=$((tries + 1))
    ((tries > 50)) && rp::die "could not acquire the ssh-key lock (another rp ssh-key add/remove is running)"
    sleep 0.1
  done
  printf '%s' "$$" >"$lock_dir/pid" 2>/dev/null
  # Run the callback in a subshell with its own EXIT trap so the lock is removed
  # even if the callback dies via `exit` (e.g. rp::notfound inside an add/remove,
  # which the outer `return` would otherwise skip). The outer cleanup covers the
  # normal return path; the inner covers the exit path.
  (
    _sshkey_unlock() {
      # shellcheck disable=SC2317
      rm -f "$lock_dir/pid" 2>/dev/null
      # shellcheck disable=SC2317
      rmdir "$lock_dir" 2>/dev/null
    }
    trap _sshkey_unlock EXIT
    "$fn" "$@"
  )
  local rc=$?
  rm -f "$lock_dir/pid" 2>/dev/null
  rmdir "$lock_dir" 2>/dev/null
  return "$rc"
}

# stdin: one authorized-key line -> its SHA256 fingerprint (empty if ssh-keygen missing)
_sshkey_fp() {
  command -v ssh-keygen >/dev/null 2>&1 || return 0
  ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || true
}

_sshkey_list_human() {
  printf '%s\t%s\t%s\n' "TYPE" "FINGERPRINT" "KEY"
  local fp line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_sshkey_fp <<<"$line")"
    printf '%s\t%s\t%s\n' "${line%% *}" "${fp:--}" "${line:0:64}"
  done <<<"$1"
}

_sshkey_list() {
  local raw keys_json keys
  raw="$(rp::http GET "/account/ssh-keys")"
  keys_json="$(printf '%s' "$raw" | jq -c '.keys // []')"
  keys="$(printf '%s' "$raw" | jq -r '.keys // [] | join("\n")')"
  rp::emit_json_or "$keys_json" _sshkey_list_human "$keys"
}

_sshkey_add_unlocked() {
  local newkey="$1"
  local raw keys_json line
  raw="$(rp::http GET "/account/ssh-keys")"
  keys_json="$(printf '%s' "$raw" | jq -c '.keys // []')"
  local -a keys=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == "$newkey" ]]; then
      rp::ok "key already registered"
      return 0
    fi
    keys+=("$line")
  done < <(printf '%s' "$keys_json" | jq -r '.[]')
  keys+=("$newkey")
  rp::http PUT "/account/ssh-keys" "$(rp::json_obj keys "$(rp::json_array "${keys[@]}")")" >/dev/null
  rp::ok "added key"
}

_sshkey_add() {
  local src newkey
  src="$(rp::args_pos)"
  if [[ -z "$src" || "$src" == "-" ]]; then
    newkey="$(cat)"
  else
    [[ -r "$src" ]] || rp::notfound "cannot read key file: $src"
    newkey="$(<"$src")"
  fi
  newkey="$(printf '%s' "$newkey" | awk 'NF' | head -n1)"
  [[ -n "$newkey" ]] || rp::usage "usage: rp ssh-key add <file|->: no key found in input"
  _sshkey_locked _sshkey_add_unlocked "$newkey"
}

_sshkey_remove_unlocked() {
  local target="$1"
  local raw keys_json fp matches=0 line
  raw="$(rp::http GET "/account/ssh-keys")"
  keys_json="$(printf '%s' "$raw" | jq -c '.keys // []')"
  local -a keep=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_sshkey_fp <<<"$line")"
    if [[ "$fp" == "$target" || "$line" == *"$target"* ]]; then
      matches=$((matches + 1))
    else
      keep+=("$line")
    fi
  done < <(printf '%s' "$keys_json" | jq -r '.[]')
  ((matches)) || rp::notfound "no matching key found for '$target'"
  ((matches == 1)) || rp::usage "usage: rp ssh-key remove '$target' is ambiguous ($matches keys match); use a longer fingerprint or key substring"
  rp::http PUT "/account/ssh-keys" "$(rp::json_obj keys "$(rp::json_array "${keep[@]}")")" >/dev/null
  rp::ok "removed key"
}

_sshkey_remove() {
  local target
  rp::require_pos target "usage: rp ssh-key remove <fingerprint|key>"
  _sshkey_locked _sshkey_remove_unlocked "$target"
}

###
### :::: documentation (rp doc ssh-key) :::: ##################################
###

# doc: list
# List your registered public keys (API v2 REST plane).
#
# Usage: rp ssh-key list [--json]
#
# Options:
#   --json  print the keys as a JSON array of authorized-key lines
#
# Notes:
#   This is the v2 REST equivalent of `rp ssh list-keys` (which still uses
#   GraphQL). The table shows the key type, its SHA256 fingerprint, and the
#   first 64 characters of the key itself.
#
# API: GET /v2/account/ssh-keys

# doc: add
# Add a public key from a file or stdin (API v2 REST plane).
#
# Usage: rp ssh-key add <file|->
#
# Arguments:
#   <file|->  public-key file to read; - or no argument reads stdin
#
# Notes:
#   Only the first non-blank line of the input is registered. Re-adding a key
#   you already hold is a no-op.
#   The write is read-modify-write: the whole set is fetched, appended to, and
#   PUT back (the v2 route replaces the entire key set), so two adds racing from
#   the same host are serialised behind a lock.
#
# Examples:
#   rp ssh-key add ~/.ssh/id_ed25519.pub
#   ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -
#
# API: GET then PUT /v2/account/ssh-keys

# doc: remove
# Remove a registered public key (API v2 REST plane).
#
# Usage: rp ssh-key remove <fingerprint|key>
#
# Arguments:
#   <fingerprint|key>  SHA256 fingerprint from `rp ssh-key list`, or any
#                      substring of the key line
#
# Notes:
#   Exactly one key must match. A fingerprint is compared whole and anything
#   else as a substring, so a fragment that hits several keys is rejected rather
#   than removing them all.
#   The surviving keys are written back via a full-set PUT.
#
# Examples:
#   rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
#   rp ssh-key remove laptop@example.com
#
# API: GET then PUT /v2/account/ssh-keys

rp::cmd_ssh-key() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) _sshkey_list ;;
  add) _sshkey_add ;;
  remove) _sshkey_remove ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp ssh-key <verb>   (v2 REST plane — rp ssh's key verbs alias these)
  list                        list your registered public keys (GET /v2/account/ssh-keys)
  add <file|->               add a public key (file path, or - / stdin)
  remove <fingerprint|key>   remove a key by SHA256 fingerprint or key substring
EOF
    ;;
  *) rp::usage "unknown ssh-key verb: '$verb'" ;;
  esac
}
