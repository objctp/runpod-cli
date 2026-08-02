#!/usr/bin/env bash
#
# Deprecated: alias for `rp serverless` (resource renamed).
#
# `rp endpoint` was kept when the CLI moved to REST API v2 and the resource
# was renamed, so that existing scripts degrade to a warning instead of an
# "unknown resource" error. Every verb prints that warning and is then handed
# to `rp serverless` unchanged.
#
# Usage: rp endpoint <verb> [flags]
#
# Notes:
#   Deprecated — use `rp serverless <verb>` instead.
#   All verbs and flags are those of `rp serverless`; see `rp doc serverless`.
#
# API: none of its own — delegates to `rp serverless`.
#
. "${BASH_SOURCE[0]%/*}/serverless.sh"

###
### :::: documentation (rp doc endpoint) :::: #################################
###

rp::cmd_endpoint() {
  rp::warn "'rp endpoint' is deprecated — use 'rp serverless'"
  rp::cmd_serverless "$@"
}
