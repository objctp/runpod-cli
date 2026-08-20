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
  rp::http() { printf '{"gpus":[{"id":"NVIDIA A100 80GB PCIe","pool":"AMPERE_80"},{"id":"NVIDIA A100-SXM4-80GB","pool":"AMPERE_80"}]}'; }
  _RP_GPU_POOLS="" # bypass the process cache
  local pools
  pools="$(rp::gpu_type_to_pool_csv "NVIDIA A100 80GB PCIe")"
  assert_equals "AMPERE_80" "$pools"
  rp::http() { :; }
}

function test_gpu_type_to_pool_returns_empty_for_unknown_type() {
  rp::http() { printf '{"gpus":[{"id":"NVIDIA A100 80GB PCIe","pool":"AMPERE_80"}]}'; }
  _RP_GPU_POOLS=""
  local pools
  pools="$(rp::gpu_type_to_pool_csv "NVIDIA Bogus 9000")"
  assert_empty "$pools"
  rp::http() { :; }
}

# main-shell variants (bashunit skips lines run inside $(...)) so the public hub
# helpers register coverage.
function test_should_resolve_pool_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::http() { printf '{"gpus":[{"id":"NVIDIA A100 80GB PCIe","pool":"AMPERE_80"}]}'; }
  _RP_GPU_POOLS=""
  rp::gpu_type_to_pool_csv "NVIDIA A100 80GB PCIe" >"$tmp"
  assert_equals "AMPERE_80" "$(<"$tmp")"
  rp::http() { :; }
  rm -f "$tmp"
}

function test_should_return_empty_for_empty_input() {
  rp::gpu_type_to_pool_csv ""
  assert_successful_code "$?"
}

function test_should_return_empty_for_empty_input_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::gpu_type_to_pool_csv "" >"$tmp"
  assert_empty "$(<"$tmp")"
  rm -f "$tmp"
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

function test_hub_list_calls_listings_without_search_query() {
  local log
  log="$(mktemp)"
  rp::graphql() {
    printf '%s\t%s' "$1" "$2" >"$log"
    printf '{"listings":[]}'
  }
  rp::hub_list "" "" "" "" "" "" ""
  local captured
  captured="$(<"$log")"
  assert_not_contains "searchQuery" "$captured"
  assert_contains "listings(input:\$input)" "$captured"
  rm -f "$log"
  rp::graphql() { :; }
}

function test_hub_list_passes_each_filter_flag_to_listings_input() {
  local log
  log="$(mktemp)"
  rp::graphql() {
    printf '%s' "$2" >"$log"
    printf '{"listings":[]}'
  }
  rp::hub_list "cat" "createdAt" "ASC" "someowner" "10" "5" ""
  local captured
  captured="$(<"$log")"
  assert_contains '"category":"cat"' "$captured"
  assert_contains '"orderBy":"createdAt"' "$captured"
  assert_contains '"orderDirection":"ASC"' "$captured"
  assert_contains '"owner":"someowner"' "$captured"
  assert_contains '"limit":10' "$captured"
  assert_contains '"offset":5' "$captured"
  rm -f "$log"
  rp::graphql() { :; }
}

function test_hub_list_omits_unset_filters_from_listings_input() {
  local log
  log="$(mktemp)"
  rp::graphql() {
    printf '%s' "$2" >"$log"
    printf '{"listings":[]}'
  }
  rp::hub_list "" "" "" "" "" "" ""
  local captured
  captured="$(<"$log")"
  assert_not_contains "category" "$captured"
  assert_not_contains "orderBy" "$captured"
  assert_not_contains "owner" "$captured"
  rm -f "$log"
  rp::graphql() { :; }
}

function test_hub_list_filters_type_client_side() {
  local fixture
  fixture='{"listings":[{"id":"a","title":"V","repoOwner":"o","repoName":"r","type":"SERVERLESS"},{"id":"b","title":"P","repoOwner":"o","repoName":"r","type":"POD"}]}'
  rp::graphql() { printf '%s' "$fixture"; }
  local data
  data="$(rp::hub_list "" "" "" "" "" "" "POD")"
  assert_contains '"id":"b"' "$data"
  assert_not_contains '"id":"a"' "$data"
  rp::graphql() { :; }
}

function test_hub_list_command_threads_flags_and_filters_type() {
  local fixture log
  fixture='{"listings":[{"id":"a","title":"V","repoOwner":"o","repoName":"r","type":"SERVERLESS"},{"id":"b","title":"P","repoOwner":"o","repoName":"r","type":"POD"}]}'
  log="$(mktemp)"
  rp::graphql() {
    printf '%s' "$2" >"$log"
    printf '%s' "$fixture"
  }
  local out
  out="$(rp::cmd_hub list --category cat --order-by createdAt --order-dir ASC --owner o --limit 10 --offset 0 --type POD)"
  local captured
  captured="$(<"$log")"
  assert_contains '"category":"cat"' "$captured"
  assert_contains '"orderBy":"createdAt"' "$captured"
  assert_contains "P" "$out"
  assert_not_contains "V" "$out"
  rm -f "$log"
  rp::graphql() { :; }
}

function test_hub_list_command_accepts_lowercase_type() {
  local fixture
  fixture='{"listings":[{"id":"a","title":"V","repoOwner":"o","repoName":"r","type":"SERVERLESS"},{"id":"b","title":"P","repoOwner":"o","repoName":"r","type":"POD"}]}'
  rp::graphql() { printf '%s' "$fixture"; }
  local out
  out="$(rp::cmd_hub list --type pod)"
  assert_contains "P" "$out"
  assert_not_contains "V" "$out"
  rp::graphql() { :; }
}
