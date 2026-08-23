#!/usr/bin/env bash
# Credential resolution — the single seam that knows where the Runpod API token
# comes from. The transport (lib/transport.sh) calls rp::auth_header and never
# reads RUNPOD_API_KEY itself, so the token source is swappable without touching
# curl. Two adapters today, both resolving to a bare token on stdout:
#   - RUNPOD_API_KEY        (env var)
#   - RUNPOD_API_KEY_FILE   (a file holding the token, e.g. a mounted K8s secret)
# Add a third (keychain, 1Password, SSO) by extending rp::auth_token alone.
[[ -n "${_RP_AUTH:-}" ]] && return 0
_RP_AUTH=1

# Resolve the account name to use, in priority order:
#   --account flag / RP_ACCOUNT env > active pointer > "default" file >
#   the single account file present (if exactly one) > none.
rp::_account_name() {
  local name
  name="${RP_ACCOUNT:-}"
  if [[ -z "$name" && -n "${RP_ARGS[*]:-}" ]]; then
    name="$(rp::args_get account 2>/dev/null)"
  fi
  [[ -n "$name" ]] && {
    printf '%s' "$name"
    return 0
  }
  [[ -f "$RP_ACTIVE_FILE" ]] && {
    cat "$RP_ACTIVE_FILE"
    return 0
  }
  [[ -f "$RP_CREDS_DIR/default" ]] && {
    printf 'default'
    return 0
  }
  local -a names=()
  if [[ -d "$RP_CREDS_DIR" ]]; then
    local f
    for f in "$RP_CREDS_DIR"/*; do
      [[ -f "$f" ]] || continue
      names+=("$(basename "$f")")
    done
  fi
  ((${#names[@]} == 1)) && {
    printf '%s' "${names[0]}"
    return 0
  }
  return 1
}

# Load the resolved account's file into the environment. Explicit exported
# credentials always win; anything rp loaded from a file (legacy .env, install
# .env) may be overridden by a selected account. No-op when nothing resolves.
rp::_load_account() {
  if [[ -n "${RUNPOD_API_KEY:-}" || -n "${RUNPOD_API_KEY_FILE:-}" ]]; then
    [[ -z "${RP_ENV_SRC[RUNPOD_API_KEY]:-}${RP_ENV_SRC[RUNPOD_API_KEY_FILE]:-}" ]] && return 0
  fi
  local name file
  name="$(rp::_account_name)" || return 0
  file="$RP_CREDS_DIR/$name"
  [[ -f "$file" ]] || return 0
  # Force-load so the selected account overrides any lower-priority source
  # already in the environment (e.g. the install-local .env loaded at startup).
  _rp_env_load "$file" force
}

# Resolve the API token from the configured source; print it on stdout. Dies
# (exit 3) if neither source is set. The caller must keep it off argv — pipe it
# to a header file via rp::auth_header, never interpolate it into a command line.
#
# Resolution order (highest priority first):
#   1. RUNPOD_API_KEY / RUNPOD_API_KEY_FILE already in the environment (explicit)
#   2. the selected account file (credentials.d/<name>, via `rp::_load_account`:
#      --account flag / RP_ACCOUNT env / active pointer / "default" / the single
#      account present)
#   3. the legacy per-user .env ($RP_CONFIG_HOME/.env)
#   4. the install-local .env ($RP_ROOT/.env)
rp::auth_token() {
  # Keep the token off `set -x` (bash -x) traces as well as off curl's argv:
  # save xtrace state, silence it for the duration, and restore it on return.
  local _rp_xtrace
  _rp_xtrace="$(rp::_xtrace_save)"
  set +x
  # Honour a selected account (or the active pointer) before reading env.
  rp::_load_account 2>/dev/null || true
  if [[ -n "${RUNPOD_API_KEY:-}" ]]; then
    printf '%s' "$RUNPOD_API_KEY"
  elif [[ -n "${RUNPOD_API_KEY_FILE:-}" ]]; then
    [[ -f "$RUNPOD_API_KEY_FILE" ]] || rp::die "RUNPOD_API_KEY_FILE points to a missing file: $RUNPOD_API_KEY_FILE"
    # Trim a trailing newline so the Bearer value is exact (files end in \n).
    printf '%s' "$(tr -d '\n' <"$RUNPOD_API_KEY_FILE")"
  else
    _auth "RUNPOD_API_KEY unset — run 'rp auth login', or set RUNPOD_API_KEY / RUNPOD_API_KEY_FILE"
  fi
  rp::_xtrace_restore "$_rp_xtrace"
}

# Print the full Authorization header line for curl's -H @"file" consumption.
# The token crosses a pipe (not argv), so it never appears in `ps`. xtrace is
# silenced around the build so `set -x` never prints the token in the trace.
rp::auth_header() {
  local _rp_xtrace
  _rp_xtrace="$(rp::_xtrace_save)"
  set +x
  printf 'Authorization: Bearer %s\n' "$(rp::auth_token)"
  rp::_xtrace_restore "$_rp_xtrace"
}
