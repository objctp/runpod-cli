#!/usr/bin/env bash
# Documentation acceptance for ticket 10-docs-compat: every runpodctl-compatible
# flag alias must be discoverable in the command --help text and the `rp doc`
# reference blocks. This is a doc-only ticket, so the assertions inspect rendered
# output rather than transport behaviour.
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Run the real CLI binary so we assert what a user actually sees. `--help` and
# `doc` never touch the network, so no API key is required.
_rp() { bash "$RP_ROOT/bin/rp" "$@"; }

# The nine key-copy aliases, as (canonical-flag, runpodctl-alias-flag) pairs.
ALIASES=(
  "--gpu|--gpu-id"
  "--dc|--data-center-ids"
  "--container-disk-gb|--container-disk-in-gb"
  "--volume-gb|--volume-in-gb"
  "--volume-path|--volume-mount-path"
  "--registry|--registry-auth-id"
  "--cloud|--cloud-type"
  "--start-cmd|--docker-args"
  "--docker-cmd|--docker-start-cmd"
)

function test_pod_help_shows_key_copy_aliases() {
  local out
  out="$(_rp pod --help)"
  local pair canonical alias
  for pair in "${ALIASES[@]}"; do
    canonical="${pair%%|*}"
    alias="${pair##*|}"
    case "$canonical" in
    --gpu | --dc | --container-disk-gb | --volume-gb | --volume-path | --registry | --cloud | --start-cmd)
      assert_contains "alias: $alias" "$out"
      ;;
    esac
  done
}

function test_pod_doc_create_shows_aliases_and_coercions() {
  local out
  out="$(_rp doc pod create)"
  assert_contains "alias: --gpu-id" "$out"
  assert_contains "alias: --data-center-ids" "$out"
  assert_contains "alias: --container-disk-in-gb" "$out"
  assert_contains "alias: --volume-in-gb" "$out"
  assert_contains "alias: --volume-mount-path" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "alias: --cloud-type" "$out"
  assert_contains "alias: --docker-args" "$out"
  assert_contains "runpodctl coercion" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_pod_doc_update_shows_aliases() {
  local out
  out="$(_rp doc pod update)"
  assert_contains "alias: --container-disk-in-gb" "$out"
  assert_contains "alias: --volume-in-gb" "$out"
  assert_contains "alias: --volume-mount-path" "$out"
  assert_contains "alias: --docker-args" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_serverless_help_shows_aliases_and_coercions() {
  local out
  out="$(_rp serverless --help)"
  assert_contains "alias: --gpu-id" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "runpodctl coercion" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_serverless_doc_create_shows_aliases() {
  local out
  out="$(_rp doc serverless create)"
  assert_contains "alias: --gpu-id" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_serverless_doc_update_shows_scale_coercions() {
  local out
  out="$(_rp doc serverless update)"
  assert_contains "alias: --gpu-id" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "runpodctl coercion: maps to --scaler-type" "$out"
  assert_contains "runpodctl coercion: maps to --scaler-value" "$out"
}

function test_template_help_shows_aliases() {
  local out
  out="$(_rp template --help)"
  assert_contains "alias: --docker-start-cmd" "$out"
  assert_contains "alias: --volume-in-gb" "$out"
  assert_contains "alias: --volume-mount-path" "$out"
  assert_contains "alias: --container-disk-in-gb" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_template_doc_create_shows_aliases() {
  local out
  out="$(_rp doc template create)"
  assert_contains "alias: --docker-start-cmd" "$out"
  assert_contains "alias: --volume-in-gb" "$out"
  assert_contains "alias: --volume-mount-path" "$out"
  assert_contains "alias: --container-disk-in-gb" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_template_doc_update_shows_aliases() {
  local out
  out="$(_rp doc template update)"
  assert_contains "alias: --docker-start-cmd" "$out"
  assert_contains "alias: --volume-in-gb" "$out"
  assert_contains "alias: --volume-mount-path" "$out"
  assert_contains "alias: --container-disk-in-gb" "$out"
  assert_contains "alias: --registry-auth-id" "$out"
  assert_contains "NOT aliased to runpodctl" "$out"
}

function test_volume_help_shows_dc_alias() {
  local out
  out="$(_rp volume --help)"
  assert_contains "alias: --data-center-ids" "$out"
}

function test_volume_doc_create_shows_dc_alias() {
  local out
  out="$(_rp doc volume create)"
  assert_contains "alias: --data-center-ids" "$out"
}
