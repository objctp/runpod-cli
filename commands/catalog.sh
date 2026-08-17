#!/usr/bin/env bash
#
# Catalog templates: browse the public template library.
#
# Distinct from the `template` Resource (your own private/serverless
# templates). Catalog templates are read-only here — the v2 surface exposes
# GET /v2/catalog/templates only, so there is no create/get-by-id/delete. Use
# `rp catalog list` to browse and copy an id into `rp pod create --template-id`
# or `rp serverless create --template-id`.
#
# Usage: rp catalog <verb> [flags]
#

###
### :::: documentation (rp doc catalog) :::: ##################################
###

# doc: list
# List public catalog templates (id, name, image, flags).
#
# Usage: rp catalog list [--json] [--jq <filter>] [--limit N] [--cursor <c>]
#
# Options:
#   --limit N      return at most N templates
#   --cursor <c>   offset to resume from; pairs with --limit
#   --jq <filter>  jq filter applied to the array
#   --json         print the raw API response
#
# Notes:
#   These are the community catalog templates, not your own `template` Resource
#   entries. The v2 catalog surface is list-only, so there is no get/delete here
#   — copy a template id into `rp pod create --template-id` or
#   `rp serverless create --template-id` to use one.
#   `serverless` marks templates built for serverless workers; `public` marks
#   templates visible to other Runpod users.
#
# API: GET /v2/catalog/templates

rp::cmd_catalog() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  list) rp::resource_list catalog --reshape 'map({id, name, image, serverless, public})' id name image serverless public ;;
  -h | --help | help)
    cat <<'EOF'
Usage: rp catalog <verb> [flags]
  list   list public catalog templates (id, name, image, serverless, public)
EOF
    ;;
  *) rp::usage "unknown catalog verb: '$verb'" ;;
  esac
}
