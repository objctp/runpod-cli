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
  local keys_json="$1" line fp obj
  local -a rows=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="$(_sshkey_fp <<<"$line")"
    obj="$(rp::json_obj \
      TYPE "$(rp::json_str "${line%% *}")" \
      FINGERPRINT "$(rp::json_str "${fp:--}")" \
      KEY "$(rp::json_str "${line:0:64}")")"
    rows+=("$obj")
  done < <(printf '%s' "$keys_json" | jq -r '.[]?')
  rp::table "$(printf '%s\n' "${rows[@]}" | jq -sc .)" TYPE FINGERPRINT KEY
}

_sshkey_list() {
  local raw keys_json
  raw="$(rp::http GET "/account/ssh-keys")"
  keys_json="$(printf '%s' "$raw" | jq -c '.keys // []')"
  rp::emit_json_or "$keys_json" _sshkey_list_human "$keys_json"
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

# Generate an SSH key pair and print the public key on stdout (the caller
# registers it). When `rp ssh-key add` is given no input, a fresh pair is
# created under $RP_CONFIG_HOME/ssh/<name> and the private key is persisted
# locally so `rp ssh` can use it later. <name> defaults to "rp-ssh-key" and is
# overridable via --name.
_sshkey_generate() {
  local name="${1:-rp-ssh-key}" keytype="${2:-rsa}"
  case "$keytype" in
  rsa | ed25519) ;;
  *) rp::usage "invalid --type '$keytype' (expected rsa|ed25519)" ;;
  esac
  local ssh_dir key_path pub_path
  ssh_dir="$RP_CONFIG_HOME/ssh"
  if ! mkdir -p "$ssh_dir" 2>/dev/null || ! chmod 700 "$ssh_dir" 2>/dev/null; then
    rp::die "cannot create SSH key directory: $ssh_dir"
  fi
  key_path="$ssh_dir/$name"
  pub_path="$key_path.pub"
  if [[ -e "$key_path" || -e "$pub_path" ]] && ! rp::args_has force; then
    rp::die "key '$name' already exists in $ssh_dir (use --force to overwrite)"
  fi
  command -v ssh-keygen >/dev/null 2>&1 || rp::die "ssh-keygen not found; cannot generate a key"
  if [[ -t 0 ]] && ! rp::args_has force; then
    local ans
    printf '%s' "Generate a new $keytype SSH key in $ssh_dir and register it with Runpod? [y/N] " >&2
    IFS= read -r ans || true
    [[ "${ans,,}" == y* ]] || {
      rp::ok "aborted"
      return 1
    }
  fi
  local -a kt_args=(-t "$keytype")
  [[ "$keytype" == "rsa" ]] && kt_args+=(-b 2048)
  ssh-keygen "${kt_args[@]}" -f "$key_path" -N "" -C "$name" >&2 ||
    rp::die "ssh-keygen failed"
  chmod 600 "$key_path" 2>/dev/null
  chmod 644 "$pub_path" 2>/dev/null
  rp::ok "saved key pair: $key_path (private), $pub_path (public)"
  cat "$pub_path"
}

# Copy a runpodctl private key into rp's store so `rp ssh` can use it for
# connections. Skips when rp already holds a key of the same name; the public
# half is what gets registered, this just preserves local usability.
_sshkey_copy_private() {
  local pub="$1" rpc_priv rpc_name rp_priv rp_dir
  rpc_priv="${pub%.pub}"
  rpc_name="$(basename "$rpc_priv")"
  rp_dir="$RP_CONFIG_HOME/ssh"
  rp_priv="$rp_dir/$rpc_name"
  [[ -e "$rpc_priv" ]] || return 0
  [[ -e "$rp_priv" ]] && return 0
  mkdir -p "$rp_dir" 2>/dev/null && chmod 700 "$rp_dir" 2>/dev/null
  cp "$rpc_priv" "$rp_priv" 2>/dev/null && chmod 600 "$rp_priv" 2>/dev/null &&
    rp::info "copied private key to $rp_priv"
}

# Import runpodctl's locally-stored SSH keys (under ~/.runpod/ssh) and register
# any whose public half is not yet on the Runpod account. Runs as a single
# read-modify-write so the account set is updated atomically.
_sshkey_import_runpodctl() {
  local rpc_dir="${RUNPODCTL_SSH_DIR:-$HOME/.runpod/ssh}"
  [[ -d "$rpc_dir" ]] || rp::die "no runpodctl ssh directory found at $rpc_dir"
  local -a pubs=()
  local p
  for p in "$rpc_dir"/*.pub; do
    [[ -f "$p" ]] || continue
    pubs+=("$p")
  done
  ((${#pubs[@]})) || {
    rp::info "no public keys found in $rpc_dir"
    return 0
  }
  _sshkey_locked _sshkey_import_unlocked "${pubs[@]}"
}

_sshkey_import_unlocked() {
  local raw keys_json line
  local -a pubs=("$@") server=() added=0 skipped=0 keyline p
  local rpc_dir="${pubs[0]%/*}"
  raw="$(rp::http GET "/account/ssh-keys")"
  keys_json="$(printf '%s' "$raw" | jq -c '.keys // []')"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    server+=("$line")
  done < <(printf '%s' "$keys_json" | jq -r '.[]')
  for p in "${pubs[@]}"; do
    keyline="$(awk 'NF' "$p" | head -n1)"
    [[ -n "$keyline" ]] || {
      rp::warn "skipping unreadable key: $p"
      continue
    }
    local found=0 s
    for s in "${server[@]}"; do
      [[ "$s" == "$keyline" ]] && found=1 && break
    done
    if ((found)); then
      skipped=$((skipped + 1))
    else
      server+=("$keyline")
      added=$((added + 1))
      _sshkey_copy_private "$p"
    fi
  done
  if ((added)); then
    rp::http PUT "/account/ssh-keys" "$(rp::json_obj keys "$(rp::json_array "${server[@]}")")" >/dev/null
  fi
  rp::ok "imported $added key(s) from $rpc_dir ($skipped already registered)"
}

_sshkey_add() {
  local src key_file raw_key name keytype newkey
  src="$(rp::args_pos)"
  key_file="$(rp::args_get key-file)"
  raw_key="$(rp::args_get key)"
  name="$(rp::args_get name)"
  keytype="$(rp::args_get type rsa)"
  if rp::args_has from-runpodctl; then
    _sshkey_import_runpodctl
    return $?
  fi
  if [[ -n "$raw_key" ]]; then
    newkey="$raw_key"
  elif [[ -n "$key_file" || -n "$src" ]]; then
    local f="${key_file:-$src}"
    if [[ -z "$f" || "$f" == "-" ]]; then
      newkey="$(cat)"
    else
      [[ -r "$f" ]] || rp::notfound "cannot read key file: $f"
      newkey="$(<"$f")"
    fi
  else
    newkey="$(_sshkey_generate "$name" "$keytype")" || return $?
  fi
  newkey="$(printf '%s' "$newkey" | awk 'NF' | head -n1)"
  [[ -n "$newkey" ]] || rp::usage "usage: rp ssh-key add <file|-> [--key-file <path>] [--key <pub>]: no key found in input"
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
# List your registered public keys.
#
# Usage: rp ssh-key list [--json]
#
# Options:
#   --json  print the keys as a JSON array of authorized-key lines
#
# Notes:
#   This is the canonical key command; `rp ssh list-keys` is a deprecated
#   shim that warns and delegates here (same v2 REST route). The table shows
#   the key type, its SHA256 fingerprint, and the first 64 characters of the
#   key itself.
#
# API: GET /v2/account/ssh-keys

# doc: add
# Add a public key from a file, stdin, or generate a fresh pair.
#
# Usage: rp ssh-key add [<file|>] [--key-file <path>] [--key <pub>] [--name <n>] [--type rsa|ed25519] [--force] [--from-runpodctl]
#
# Arguments:
#   <file|->  public-key file to read; - or no argument reads stdin. When no
#             file, --key, --key-file, or --from-runpodctl is given, a new key
#             pair is generated and registered instead.
#
# Options:
#   --key-file <path>   read the public key from this file (alias of the positional)
#   --key <pub>         register this public-key string directly
#   --name <n>          name for a generated key (default: rp-ssh-key)
#   --type rsa|ed25519  algorithm for a generated key (default: rsa, 2048-bit)
#   --force             overwrite an existing generated key of the same name
#                       without prompting
#   --from-runpodctl    import every public key found under runpodctl's ssh
#                       directory (~/.runpod/ssh); the matching private keys are
#                       copied into $RP_CONFIG_HOME/ssh
#
# Notes:
#   A generated pair is written to $RP_CONFIG_HOME/ssh/<name> (private, 0600)
#   and <name>.pub (public, 0644) so it can be reused for pod connections; only
#   the public half is sent to Runpod. Generation prompts for confirmation on a
#   TTY unless --force is given. Only the first non-blank line of a supplied key
#   is registered, and re-adding a key you already hold is a no-op.
#   `--from-runpodctl` de-duplicates against the account's existing key set, so
#   re-running it is safe: already-registered keys are skipped.
#   The write is read-modify-write: the whole set is fetched, appended to, and
#   PUT back (the v2 route replaces the entire key set), so two adds racing from
#   the same host are serialised behind a lock.
#
# Examples:
# # Add a public key from a file
# $ rp ssh-key add ~/.ssh/id_ed25519.pub
# # Pipe a public key straight from ssh-keygen
# $ ssh-keygen -y -f ~/.ssh/id_ed25519 | rp ssh-key add -
# # Generate a fresh key pair and register it
# $ rp ssh-key add
# # Migrate runpodctl's keys into rp and register any missing from the account
# $ rp ssh-key add --from-runpodctl
#
# API: GET then PUT /v2/account/ssh-keys

# doc: remove
# Remove a registered public key.
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
# # Remove a key by its fingerprint
# $ rp ssh-key remove SHA256:2yKPqJ4hTVEnBmvJ5vHJd0LmqUTAqZk0lQbHkbG0kQE
# # Remove a key by its comment/email
# $ rp ssh-key remove laptop@example.com
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
  add [<file|->] [--key-file <path>] [--key <pub>] [--name <n>] [--type rsa|ed25519] [--force] [--from-runpodctl]
                             add a public key (file, - / stdin), generate one, or import from runpodctl
  remove <fingerprint|key>   remove a key by SHA256 fingerprint or key substring
EOF
    ;;
  *) rp::usage "unknown ssh-key verb: '$verb'" ;;
  esac
}
