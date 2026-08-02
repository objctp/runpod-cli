#!/usr/bin/env bash
#
# Update rp in place from the latest (or a pinned) release.
#
# The public installer is fetched from GitHub and re-run: it re-extracts rp
# into ~/.rp and refreshes the /usr/local/bin/rp symlink, so an upgrade
# replaces the whole install rather than patching it. --version pins the
# installer to a tagged release, running that tag's own installer against that
# tag's payload, so a downgrade behaves the same way as an upgrade.
#
# Usage: rp upgrade [--version <x.y.z>]
#
# Options:
#   --version <x.y.z>  pin the installer to a tagged release (default: latest)
#
# Notes:
#   The /usr/local/bin/rp symlink step may prompt for sudo.
#
# Examples:
#   rp upgrade
#   rp upgrade --version 1.2.3
#
# API: none — downloads and runs the installer from GitHub (RP_UPGRADE_REPO).
#

###
### :::: documentation (rp doc upgrade) :::: ##################################
###

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
    url="https://raw.githubusercontent.com/${RP_UPGRADE_REPO}/v${ver_arg}/install.sh"
  else
    url="https://raw.githubusercontent.com/${RP_UPGRADE_REPO}/main/install.sh"
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
