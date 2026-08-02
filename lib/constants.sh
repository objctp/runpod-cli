#!/usr/bin/env bash
#
# RunPod CLI — tunable literals (the "magic values" that are NOT the API wire
# contract). Contract constants (API base URLs, REST paths, GraphQL field names,
# enum values) live closer to the code that uses them (lib/common.sh,
# lib/resource.sh) or are env-overridable; this file is the single home for the
# defaults, ceilings and magic numbers the rest of the CLI would otherwise
# hardcode inline. Scalars only — domain data tables (the GPU ranking, the model
# slug map, the S3 datacentre snapshot) live beside their one consumer instead.
# Usage: sourced by lib/common.sh, so every lib/ and commands/ file has these
#
# shellcheck disable=SC2034 # every value here is consumed by another module
[[ -n "${_RP_CONSTANTS:-}" ]] && return 0
_RP_CONSTANTS=1

# Self-sufficient RP_ROOT so this file can be sourced standalone (e.g. tests)
# without common.sh having run first; common.sh sets the same value when present.
RP_ROOT="${RP_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"

###
### :::: timeouts (seconds) :::: ###############################################
###

# curl --connect-timeout, applied on both transport planes (rest + api) and the
# SSE stream. A single short budget: we only need the TCP/TLS handshake to start.
RP_TIMEOUT_CONNECT=15

# Per-plane --max-time ceilings. The serverless data plane (RP_API_BASE) blocks
# on job completion, so it gets a longer budget than the control plane / GraphQL.
RP_TIMEOUT_REST=120
RP_TIMEOUT_GRAPHQL=120
RP_TIMEOUT_API=300

# aws s3 CLI read timeout for large network-volume transfers.
RP_TIMEOUT_S3_READ=7200

###
### :::: limits & ceilings :::: ################################################
###

# API ceiling on --tail (log lines); enforced in `rp pod logs` / `rp serverless logs`.
RP_LOG_TAIL_MAX=5000

# Default result cap for `rp hub search`.
RP_HUB_SEARCH_LIMIT=20

# Floor for --last-n (billing): must be >= 1 (the spec rejects 0).
RP_LAST_N_MIN=1

# Floor for --min-count (stock gpu), which maps to the catalog `count` query
# param — openapi.json GpuCountFilter declares `minimum: 1`.
RP_STOCK_COUNT_MIN=1

###
### :::: default sizes & paths :::: ############################################
###

# Default container mount path when --volume-path is omitted (v2 back-compat).
RP_DEFAULT_MOUNT_PATH=/workspace

# Fallback container disk when a Hub listing omits containerDiskInGb. GB, per
# openapi.json ContainerConfig.disk ("Container disk in GB", minimum 1).
RP_DEFAULT_CONTAINER_DISK_GB=20

# Default S3 key prefix for `rp volume sync --models`.
RP_DEFAULT_MODEL_PREFIX=models

# Default local cache dir for `rp volume sync --models` (overridable via RP_MODEL_CACHE).
RP_DEFAULT_MODEL_CACHE="$RP_ROOT/.cache/models"

# Default GPU count for serverless/pod create when --gpu-count is omitted.
RP_DEFAULT_GPU_COUNT=1

# Default worker min/max for `rp serverless create --hub-id` (hub listings scale from 0).
RP_DEFAULT_WORKERS_MIN=0
RP_DEFAULT_WORKERS_MAX=0

###
### :::: unit conversions :::: #################################################
###

# Seconds -> milliseconds. --execution-timeout is taken in seconds but sent as
# `timeout`, which openapi.json documents as "Per-request execution timeout in
# milliseconds" (default 300000).
RP_MS_PER_SECOND=1000

###
### :::: scaling defaults :::: #################################################
###

# Implicit scaler values when a scaler type is given without --scaler-value.
# The two arms carry different units, hence the asymmetric names — openapi.json
# ScalerType: QUEUE_DELAY scales on "seconds a request waits in queue",
# REQUEST_COUNT on "in-flight request count". 4 matches the spec's own
# CreateEndpointRequest.scaling.value default.
RP_DEFAULT_SCALER_QUEUE_DELAY_S=4
RP_DEFAULT_SCALER_REQUEST_COUNT=1

###
### :::: default enums & product choices :::: ##################################
###

# Default cloud tier for `rp pod create` (--cloud).
RP_DEFAULT_CLOUD=SECURE

# Default product filter for `rp stock gpu` (--product).
RP_DEFAULT_PRODUCT=POD,SERVERLESS

# Default endpoint type for `rp serverless create` (--type).
RP_DEFAULT_SERVERLESS_TYPE=QUEUE

# Default template category for `rp template create` (--category).
RP_DEFAULT_TEMPLATE_CATEGORY=NVIDIA

###
### :::: repo / self-update :::: ###############################################
###

# GitHub slug whose install.sh `rp upgrade` re-runs. Keep in sync with install.sh's RP_REPO.
RP_UPGRADE_REPO="objctp/runpod-cli"
