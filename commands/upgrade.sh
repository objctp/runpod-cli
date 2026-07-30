#!/usr/bin/env bash
# `rp upgrade` re-runs the public installer against the latest release (or a
# pinned one via --version). The installer re-extracts into ~/.rp and refreshes
# the /usr/local/bin/rp symlink, so this is a full in-place self-update.

# Where the public installer lives; kept in sync with install.sh's RP_REPO.
_RP_UPGRADE_REPO="objctp/runpod-cli"

rp::cmd_upgrade() {
  rp::args_parse "$@"
  if rp::args_has help; then
    echo "Usage: rp upgrade [--version <x.y.z>]   (update rp in place)"
    return
  fi

  local cur ver_arg url installer
  cur="$(rp::version)"
  ver_arg="$(rp::args_get version)"

  # Pin the installer to the matching tag when a version is requested, so a
  # downgrade runs the old installer against the old payload (not main's).
  if [[ -n "$ver_arg" ]]; then
    url="https://raw.githubusercontent.com/${_RP_UPGRADE_REPO}/v${ver_arg}/install.sh"
  else
    url="https://raw.githubusercontent.com/${_RP_UPGRADE_REPO}/main/install.sh"
  fi

  rp::info "rp ${cur} -> ${ver_arg:-latest}"
  rp::info "re-running installer (the /usr/local/bin symlink step may ask for sudo)..."

  # Download to a temp file first, then execute: piping curl straight into bash
  # would run a partially-fetched script if the connection drops mid-stream.
  # _mktemp registers the file for cleanup by bin/rp's EXIT trap.
  _mktemp installer
  curl -fsSL "$url" -o "$installer" || rp::die "installer download failed: $url"
  local -a install_args=()
  [[ -n "$ver_arg" ]] && install_args+=(--version "$ver_arg")
  bash "$installer" "${install_args[@]}"
}
