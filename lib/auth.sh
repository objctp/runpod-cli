#!/usr/bin/env bash
# Credential resolution — the single seam that knows where the RunPod API token
# comes from. The transport (lib/transport.sh) calls rp::auth_header and never
# reads RUNPOD_API_KEY itself, so the token source is swappable without touching
# curl. Two adapters today, both resolving to a bare token on stdout:
#   - RUNPOD_API_KEY        (env var)
#   - RUNPOD_API_KEY_FILE   (a file holding the token, e.g. a mounted K8s secret)
# Add a third (keychain, 1Password, SSO) by extending rp::auth_token alone.
[[ -n "${_RP_AUTH:-}" ]] && return 0
_RP_AUTH=1

# Resolve the API token from the configured source; print it on stdout. Dies
# (exit 3) if neither source is set. The caller must keep it off argv — pipe it
# to a header file via rp::auth_header, never interpolate it into a command line.
rp::auth_token() {
  # Keep the token off `set -x` (bash -x) traces as well as off curl's argv:
  # save xtrace state, silence it for the duration, and restore it on return.
  local _rp_xtrace
  _rp_xtrace="$(rp::_xtrace_save)"
  set +x
  if [[ -n "${RUNPOD_API_KEY:-}" ]]; then
    printf '%s' "$RUNPOD_API_KEY"
  elif [[ -n "${RUNPOD_API_KEY_FILE:-}" ]]; then
    [[ -f "$RUNPOD_API_KEY_FILE" ]] || rp::die "RUNPOD_API_KEY_FILE points to a missing file: $RUNPOD_API_KEY_FILE"
    # Trim a trailing newline so the Bearer value is exact (files end in \n).
    printf '%s' "$(tr -d '\n' <"$RUNPOD_API_KEY_FILE")"
  else
    _auth "RUNPOD_API_KEY unset — add it to .env (console > Settings > API Keys), or set RUNPOD_API_KEY_FILE"
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
