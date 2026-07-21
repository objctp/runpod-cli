#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/graphql.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/hub.sh"
  source "$RP_ROOT/commands/hub.sh"
  eval "$_opts"
}

function test_hub_search_returns_listings() {
  rp::graphql() { printf '{"listings":[{"id":"abc","title":"vLLM","repoOwner":"runpod-workers","repoName":"worker-vllm","type":"SERVERLESS"}]}'; }
  local data
  data="$(rp::hub_search vllm 5)"
  assert_contains "worker-vllm" "$data"
  assert_contains "SERVERLESS" "$data"
  rp::graphql() { :; }
}

function test_hub_get_returns_listing_with_image_and_config() {
  local fixture
  fixture="$(jq -c -n --arg img 'img:1' --arg cfg '{"gpuIds":"AMPERE_80","containerDiskInGb":20}' \
    '{listing:{id:"abc",title:"vLLM",listedRelease:{tagName:"v1",build:{imageName:$img},config:$cfg}}}')"
  rp::graphql() { printf '%s' "$fixture"; }
  local data
  data="$(rp::hub_get abc)"
  assert_contains "img:1" "$data"
  assert_contains "AMPERE_80" "$data"
  rp::graphql() { :; }
}

function test_gpu_type_to_pool_maps_type_name_to_pool_id() {
  rp::graphql() { printf '{"serverlessGpuPools":[{"id":"AMPERE_80","gpuTypeIds":["NVIDIA A100 80GB PCIe","NVIDIA A100-SXM4-80GB"]}]}'; }
  _RP_GPU_POOLS="" # bypass the process cache
  local pools
  pools="$(rp::gpu_type_to_pool_csv "NVIDIA A100 80GB PCIe")"
  assert_equals "AMPERE_80" "$pools"
  rp::graphql() { :; }
}

function test_gpu_type_to_pool_returns_empty_for_unknown_type() {
  rp::graphql() { printf '{"serverlessGpuPools":[{"id":"AMPERE_80","gpuTypeIds":["NVIDIA A100 80GB PCIe"]}]}'; }
  _RP_GPU_POOLS=""
  local pools
  pools="$(rp::gpu_type_to_pool_csv "NVIDIA Bogus 9000")"
  assert_empty "$pools"
  rp::graphql() { :; }
}

# main-shell variants (bashunit skips lines run inside $(...)) so the public hub
# helpers register coverage.
function test_should_resolve_pool_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::graphql() { printf '{"serverlessGpuPools":[{"id":"AMPERE_80","gpuTypeIds":["NVIDIA A100 80GB PCIe"]}]}'; }
  _RP_GPU_POOLS=""
  rp::gpu_type_to_pool_csv "NVIDIA A100 80GB PCIe" >"$tmp"
  assert_equals "AMPERE_80" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_return_empty_for_empty_input() {
  rp::gpu_type_to_pool_csv ""
  assert_successful_code "$?"
}

function test_should_search_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::graphql() { printf '{"listings":[{"id":"abc","title":"vLLM"}]}'; }
  rp::hub_search vllm 5 >"$tmp"
  assert_contains "vLLM" "$(<"$tmp")"
  rm -f "$tmp"
}

function test_should_get_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::graphql() { printf '{"listing":{"id":"abc","title":"vLLM","listedRelease":{"build":{"imageName":"img:1"}}}}'; }
  rp::hub_get abc >"$tmp"
  assert_contains "vLLM" "$(<"$tmp")"
  rm -f "$tmp"
}
