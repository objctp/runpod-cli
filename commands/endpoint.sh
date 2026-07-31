#!/usr/bin/env bash
#
# `rp endpoint` — deprecated alias for `rp serverless` (the resource was renamed
# when the CLI moved to REST API v2). Kept so existing scripts degrade to a
# warning instead of "unknown resource".
# Usage: rp endpoint <verb> [flags]   (deprecated; use: rp serverless <verb>)
#
. "${BASH_SOURCE[0]%/*}/serverless.sh"

rp::cmd_endpoint() {
  rp::warn "'rp endpoint' is deprecated — use 'rp serverless'"
  rp::cmd_serverless "$@"
}
