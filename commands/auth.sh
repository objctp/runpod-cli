#!/usr/bin/env bash
#
# Manage Runpod API credentials in a stable per-user store.
# This store survives any install method — including an npm global install
# whose files live inside node_modules and are wiped on every `npm upgrade`.
# One key per account, exactly one "active" account used for API calls,
# switchable with `rp auth switch`.
#
# Layout under $RP_CONFIG_HOME:
#   credentials.d/<name>   one account: RUNPOD_API_KEY (+ optional S3 keys)
#   active                 a file containing the name of the active account
#
# There is no OAuth/browser login — Runpod is API-key only, so `login` just
# captures and stores the key you copy from console > Settings > API Keys.
#
# Usage: rp auth <verb> [flags]
#

# The credential keys `rp auth` manages in each account file. Stored unquoted
# (no surrounding quotes) so the loader re-reads them verbatim.
_AUTH_KEYS='^(RUNPOD_API_KEY|RUNPOD_API_KEY_FILE|RUNPOD_S3_ACCESS_KEY|RUNPOD_S3_SECRET_KEY)='

# Mask a token for display: keep the first 3 and last 4 chars, elide the middle;
# short tokens (<8 chars) are fully redacted.
_auth_mask() {
  local v="$1" len=${#1}
  if ((len < 8)); then
    printf '%s' "${v//?/*}"
  else
    printf '%s…%s' "${v:0:3}" "${v: -4}"
  fi
}

# Report where $1's value came from: an explicit export (no tracked source), the
# user config ($RP_CONFIG_HOME/.env), the install .env, or an account file.
_auth_source() {
  local src="${RP_ENV_SRC[$1]:-}"
  [[ -z "$src" ]] && {
    printf 'environment (exported)'
    return
  }
  [[ "$src" == "$RP_CONFIG_HOME/.env" ]] && {
    printf 'user config (%s)' "$src"
    return
  }
  [[ "$src" == "$RP_ROOT/.env" ]] && {
    printf 'install .env (%s)' "$src"
    return
  }
  [[ "$src" == "$RP_CREDS_DIR"/* ]] && {
    printf 'account file (%s)' "$src"
    return
  }
  printf '%s' "$src"
}

# List stored account names (one per line), empty if none.
_auth_accounts() {
  [[ -d "$RP_CREDS_DIR" ]] || return 0
  local f
  for f in "$RP_CREDS_DIR"/*; do
    [[ -f "$f" ]] || continue
    basename "$f"
  done
}

_auth_active_name() {
  [[ -f "$RP_ACTIVE_FILE" ]] && cat "$RP_ACTIVE_FILE"
}

# Write one account file, preserving any non-credential lines already there, with
# the dir at 700 and the file at 600.
# Read a single KEY=VALUE from a credentials file; empty if absent.
_auth_read_key() {
  local f="$1" key="$2" line
  [[ -f "$f" ]] || return 0
  line="$(grep -E "^${key}=" "$f" 2>/dev/null | tail -1)"
  [[ -z "$line" ]] && return 0
  printf '%s' "${line#*=}"
}

_auth_write_account() {
  local name="$1" ak="$2" sak="$3" ssk="$4"
  local dir="$RP_CREDS_DIR" file tmp
  file="$dir/$name"
  mkdir -p "$dir"
  chmod 700 "$RP_CONFIG_HOME"
  chmod 700 "$dir"
  tmp="$(mktemp)"
  : >"$tmp"
  # Preserve any non-auth lines (user comments or other vars). `grep -vE`
  # exits 1 when it matches nothing, which would trip `set -e` and abort the
  # whole write — so guard with `|| true`.
  if [[ -f "$file" ]]; then
    grep -vE "$_AUTH_KEYS" "$file" >>"$tmp" 2>/dev/null || true
  fi
  # Merge: keep an existing value when the caller didn't supply one, so a
  # partial login (e.g. `rp auth login --api-key …`) preserves S3 keys set in
  # a previous call instead of wiping them.
  if [[ -f "$file" ]]; then
    [[ -z "$ak" ]] && ak="$(_auth_read_key "$file" RUNPOD_API_KEY)"
    [[ -z "$sak" ]] && sak="$(_auth_read_key "$file" RUNPOD_S3_ACCESS_KEY)"
    [[ -z "$ssk" ]] && ssk="$(_auth_read_key "$file" RUNPOD_S3_SECRET_KEY)"
  fi
  [[ -n "$ak" ]] && printf 'RUNPOD_API_KEY=%s\n' "$ak" >>"$tmp"
  [[ -n "$sak" ]] && printf 'RUNPOD_S3_ACCESS_KEY=%s\n' "$sak" >>"$tmp"
  [[ -n "$ssk" ]] && printf 'RUNPOD_S3_SECRET_KEY=%s\n' "$ssk" >>"$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

_auth_set_active() {
  printf '%s' "$1" >"$RP_ACTIVE_FILE"
  chmod 600 "$RP_ACTIVE_FILE"
}

# Print runpodctl's apiKey from its config file, empty if absent or unset.
# Honours $RUNPODCTL_CONFIG for the path; defaults to ~/.runpod/config.toml.
_auth_runpodctl_key() {
  local f="${RUNPODCTL_CONFIG:-$HOME/.runpod/config.toml}"
  [[ -f "$f" ]] || return 0
  local line val
  line="$(grep -iE '^[[:space:]]*apikey[[:space:]]*=' "$f" 2>/dev/null | head -1)"
  [[ -z "$line" ]] && return 0
  val="${line#*=}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  val="${val#\"}"
  val="${val%\"}"
  val="${val#\'}"
  val="${val%\'}"
  [[ -n "$val" ]] && printf '%s' "$val"
}

_auth_login() {
  local name api_key s3_ak s3_sk from_rpc
  name="$(rp::args_get name)"
  [[ -z "$name" ]] && name=default
  api_key="$(rp::args_get api-key)"
  s3_ak="$(rp::args_get s3-access-key)"
  s3_sk="$(rp::args_get s3-secret-key)"
  from_rpc="$(rp::args_get from-runpodctl)"
  # --from-runpodctl pulls the key from runpodctl's config (non-interactive); an
  # explicit --api-key still wins.
  if [[ -z "$api_key" && -n "$from_rpc" ]]; then
    api_key="$(_auth_runpodctl_key)"
    [[ -z "$api_key" ]] &&
      rp::die "no apiKey found in runpodctl config (${RUNPODCTL_CONFIG:-$HOME/.runpod/config.toml})"
  fi
  # Interactive capture when no key is set yet and we have a terminal.
  if [[ -z "$api_key" && -t 0 ]]; then
    # Offer to import from an existing runpodctl install before prompting fresh.
    if [[ -z "$from_rpc" ]]; then
      local rpc_key rpc_path="${RUNPODCTL_CONFIG:-$HOME/.runpod/config.toml}"
      rpc_key="$(_auth_runpodctl_key)"
      if [[ -n "$rpc_key" ]]; then
        local ans=""
        read -r -p "Import API key from runpodctl config ($rpc_path)? [y/N] " ans
        [[ "$ans" == [yY] ]] && api_key="$rpc_key"
      fi
    fi
    if [[ -z "$api_key" ]]; then
      read -s -r -p "Runpod API key (console > Settings > API Keys): " api_key
      printf '\n' >/dev/tty
      read -r -p "S3 access key (optional, empty to skip): " s3_ak
      [[ -n "$s3_ak" ]] && {
        read -s -r -p "S3 secret key: " s3_sk
        printf '\n' >/dev/tty
      }
    fi
  elif [[ -z "$api_key" && -z "$s3_ak" && ! -t 0 ]]; then
    # Piped, no flags: take the API key from the first stdin line.
    IFS= read -r api_key
  fi
  [[ -z "$api_key" && -z "$s3_ak" ]] &&
    rp::usage "no credentials given — pass --api-key, or run interactively at a terminal"
  _auth_write_account "$name" "$api_key" "$s3_ak" "$s3_sk"
  _auth_set_active "$name"
  rp::ok "stored account '$name' in $RP_CREDS_DIR/$name (mode 600); it is now active"
  rp::info "the active account's key loads automatically on every 'rp' call"
}

_auth_logout() {
  local name="${1:-}" active remaining next
  [[ -z "$name" ]] && name="$(_auth_active_name)"
  [[ -z "$name" ]] && {
    rp::info "no active account to log out"
    return 0
  }
  local file="$RP_CREDS_DIR/$name"
  [[ -f "$file" ]] || {
    rp::info "no such account: '$name'"
    return 0
  }
  rm -f "$file"
  rp::ok "removed account '$name'"
  # If the removed account was active and others remain, switch to another.
  active="$(_auth_active_name)"
  if [[ "$active" == "$name" ]]; then
    remaining="$(_auth_accounts)"
    if [[ -n "$remaining" ]]; then
      next="$(printf '%s\n' "$remaining" | head -1)"
      _auth_set_active "$next"
      rp::ok "switched active account to '$next'"
    else
      rm -f "$RP_ACTIVE_FILE"
      rp::info "no accounts remain"
    fi
  fi
}

_auth_switch() {
  local name="${1:-}"
  [[ -z "$name" ]] && rp::usage "usage: rp auth switch <name>   (see: rp auth list)"
  [[ -f "$RP_CREDS_DIR/$name" ]] || rp::die "no such account: '$name' (see: rp auth list)"
  _auth_set_active "$name"
  rp::ok "active account is now '$name'"
}

_auth_list() {
  local active name
  active="$(_auth_active_name)"
  local names
  names="$(_auth_accounts)"
  if [[ -z "$names" ]]; then
    rp::info "no accounts stored (run: rp auth login)"
    return 0
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$name" == "$active" ]]; then
      rp::ok "$name (active)"
    else
      rp::info "$name"
    fi
  done <<<"$names"
}

_auth_status() {
  rp::_load_account 2>/dev/null || true
  local ak="${RUNPOD_API_KEY:-}" akf="${RUNPOD_API_KEY_FILE:-}"
  local sak="${RUNPOD_S3_ACCESS_KEY:-}" ssk="${RUNPOD_S3_SECRET_KEY:-}"
  local acct
  acct="$(rp::_account_name 2>/dev/null)"
  printf 'ACTIVE ACCOUNT  %s\n' "${acct:-<none>}"
  if [[ -n "$ak" ]]; then
    printf 'API KEY         configured   token %s\n' "$(_auth_mask "$ak")"
    printf '  source:       %s\n' "$(_auth_source RUNPOD_API_KEY)"
  elif [[ -n "$akf" ]]; then
    printf 'API KEY         configured   via file %s\n' "$akf"
    printf '  source:       %s\n' "$(_auth_source RUNPOD_API_KEY_FILE)"
  else
    printf 'API KEY         NOT configured\n'
  fi
  if [[ -n "$sak" || -n "$ssk" ]]; then
    printf 'S3 KEYS         configured'
    [[ -n "$sak" ]] && printf '   access %s' "$(_auth_mask "$sak")"
    [[ -n "$ssk" ]] && printf '   secret %s' "$(_auth_mask "$ssk")"
    printf '\n'
  else
    printf 'S3 KEYS         NOT configured (only needed for rp volume sync)\n'
  fi
  printf 'CONFIG HOME     %s\n' "$RP_CONFIG_HOME"
}

_auth_help() {
  cat <<'EOF'
Usage: rp auth <verb> [flags]

Manage Runpod API credentials in a stable per-user store
(${XDG_CONFIG_HOME:-$HOME/.config}/rp by default) that survives any install
method, including npm global installs. Multiple accounts are supported: each is
a separate file under credentials.d/, with one marked "active" and used for all
API calls. Login is additive, switch changes the active account.

Verbs:
  login     store an account (--name <n>, else "default") and mark it active
  logout    remove an account (--name <n>, else the active one)
  switch    change the active account  (alias: use)
  list      show stored accounts, marking the active one
  status    show the active account and whether a key is configured

login flags:
  --name <n>              account name (default: "default")
  --api-key <k>           API key to store (non-interactive)
  --from-runpodctl        import the API key from runpodctl's ~/.runpod/config.toml
  --s3-access-key <k>     S3 access key (optional, for rp volume sync)
  --s3-secret-key <k>     S3 secret key (optional)
  (with no flags, prompts interactively, or reads the API key from stdin)

Any command accepts --account <name> to use a specific account for that call
(overrides the active one). An exported RUNPOD_API_KEY always wins over all.
EOF
}

###
### :::: documentation (rp doc auth) :::: ######################################
###

# doc: login
# Store a Runpod API key as an account (additive — does not replace others).
# Login marks it active; the key then loads automatically on every `rp` call.
#
# Usage: rp auth login [--name <n>] [--api-key <k>] [--from-runpodctl] [--s3-access-key <k>] [--s3-secret-key <k>]
#
# Options:
#   --name <n>            account name (default: "default")
#   --api-key <k>         API key to store (non-interactive)
#   --from-runpodctl      import the API key from runpodctl's ~/.runpod/config.toml
#   --s3-access-key <k>   S3 access key (optional, for `rp volume sync`)
#   --s3-secret-key <k>   S3 secret key (optional)
#
# Notes:
#   With no flags, prompts interactively at a terminal (input hidden), or reads
#   the API key from the first stdin line when piped. If runpodctl's config holds
#   a key, interactive login offers to import it; pass `--from-runpodctl` to take
#   it without prompting. An explicit `--api-key` always wins. Stored unquoted at
#   $RP_CONFIG_HOME/credentials.d/<name> (mode 600, dir 700); other lines there
#   are preserved. The API key is the only auth Runpod supports — no OAuth.
#
# doc: logout
# Remove an account.
# If it was active and other accounts remain, the active account switches to one of the others.
#
# Usage: rp auth logout [--name <n>]
#
# Options:
#   --name <n>            account to remove (default: the active account)
#
# doc: switch
# Change the active account — the one used for all API calls.
#
# Usage: rp auth switch <name>   (alias: rp auth use <name>)
#
# doc: use
# Alias for `rp auth switch <name>` — change the active account.
# The active account is the one used for all API calls.
#
# Usage: rp auth use <name>
#

# doc: list
# Show stored accounts, marking the active one.
#
# Usage: rp auth list
#
# doc: status
# Show the active account and whether an API key is configured.
# Reports the effective source (environment export, account file, or user/install .env).
#
# Usage: rp auth status
#
# Notes:
#   Reports the effective source: an exported environment variable, an account
#   file, the user config (.env), or the install-local .env. The token is masked.

rp::cmd_auth() {
  local verb="${1:-help}"
  shift || true
  if [[ "$verb" == "use" ]]; then
    # `rp auth use <name>` is an alias for switch.
    verb=switch
  fi
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  login) _auth_login ;;
  logout) _auth_logout "$(rp::args_get name)" ;;
  switch) _auth_switch "${1:-}" ;;
  list) _auth_list ;;
  status) _auth_status ;;
  -h | --help | help) _auth_help ;;
  *) rp::usage "unknown auth verb: '$verb' (try: rp auth --help)" ;;
  esac
}
