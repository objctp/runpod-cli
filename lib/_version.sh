#!/usr/bin/env bash
# lib/_version.sh — single source of truth for the installed rp version.
# Auto-sourced by bin/rp's lib/*.sh loop. The committed value is a dev
# placeholder; .github/workflows/release.yml overwrites it with the release tag
# when building the tarball (the repo copy stays on the placeholder), and
# `make package` does the same locally. rp::version falls back to `git describe`
# while this reads "0.0.0-dev".
# shellcheck disable=SC2034 # RP_VERSION is consumed by bin/rp, not this file
RP_VERSION="0.0.0-dev"
