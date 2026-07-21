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

  local cur ver_arg url
  cur="$(rp::version)"
  ver_arg="$(rp::args_get version)"
  url="https://raw.githubusercontent.com/${_RP_UPGRADE_REPO}/main/install.sh"

  rp::info "rp ${cur} -> ${ver_arg:-latest}"
  rp::info "re-running installer (the /usr/local/bin symlink step may ask for sudo)..."

  if [[ -n "$ver_arg" ]]; then
    curl -fsSL "$url" | bash -s -- --version "$ver_arg"
  else
    curl -fsSL "$url" | bash
  fi
}
