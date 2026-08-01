#!/usr/bin/env bash
RP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

function set_up_before_script() {
  local _opts
  _opts=$(shopt -po errexit nounset pipefail 2>/dev/null || true)
  source "$RP_ROOT/lib/common.sh"
  source "$RP_ROOT/lib/http.sh"
  source "$RP_ROOT/lib/args.sh"
  source "$RP_ROOT/lib/json.sh"
  source "$RP_ROOT/lib/validate.sh"
  source "$RP_ROOT/lib/resource.sh"
  source "$RP_ROOT/lib/s3.sh"
  source "$RP_ROOT/commands/volume.sh"
  # _volume_create calls rp::warn_unless_s3_dc -> live S3-DC query; stub it so
  # the create tests make no network calls (falls back to the static snapshot).
  _s3_dcs_live() { :; }
  # S3 seam doubles (C6/B4): capture argv of the external `aws` / `huggingface-cli`
  # binaries so the region/endpoint derivation in lib/s3.sh is exercised end-to-end.
  export RUNPOD_S3_ACCESS_KEY=test-access-key
  export RUNPOD_S3_SECRET_KEY=test-secret-key
  _aws_calls=()
  _hf_calls=()
  aws() {
    echo "AWS-DOUBLE pid=$$ args=$*" >&2
    _aws_calls+=("$*")
  }
  huggingface-cli() {
    _hf_calls+=("$*")
    local -a _a=("$@")
    local _i _dir
    for ((_i = 0; _i < ${#_a[@]}; _i++)); do
      if [[ "${_a[_i]}" == "--local-dir" ]]; then _dir="${_a[_i + 1]}"; fi
    done
    [[ -n "$_dir" ]] && mkdir -p "$_dir"
  }
  eval "$_opts"
}

function test_should_not_post_when_volume_name_already_exists() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[{"id":"abc","name":"dup","size":10,"dataCenterId":"EU-RO-1"}]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"abc"}'
    fi
  }
  rp::args_parse --name dup --size 10 --dc EU-RO-1
  out="$(_volume_create 2>/dev/null)"
  assert_equals "abc" "$out"
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_post_when_volume_name_is_new() {
  local marker out
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf 'POSTED' >>"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name fresh --size 10 --dc EU-RO-1
  out="$(_volume_create 2>/dev/null)"
  assert_equals "new1" "$out"
  assert_equals "POSTED" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

# Capture the POST body ($3) so the create-time `--type` tier is asserted.
function test_create_sends_type_when_given() {
  local marker body
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name n --size 10 --dc EU-RO-1 --type HIGH_PERFORMANCE
  _volume_create >/dev/null 2>&1
  body="$(<"$marker")"
  assert_equals "HIGH_PERFORMANCE" "$(printf '%s' "$body" | jq -r '.type')"
  rp::http() { :; }
  rm -f "$marker"
}

function test_create_omits_type_when_absent() {
  local marker body
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name n --size 10 --dc EU-RO-1
  _volume_create >/dev/null 2>&1
  body="$(<"$marker")"
  assert_equals "false" "$(printf '%s' "$body" | jq -r 'has("type")')"
  rp::http() { :; }
  rm -f "$marker"
}

function test_create_accepts_standard_type() {
  local marker body
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name n --size 10 --dc EU-RO-1 --type STANDARD
  _volume_create >/dev/null 2>&1
  body="$(<"$marker")"
  assert_equals "STANDARD" "$(printf '%s' "$body" | jq -r '.type')"
  rp::http() { :; }
  rm -f "$marker"
}

function test_create_normalises_type_case() {
  local marker body
  marker="$(mktemp)"
  rp::http() {
    if [[ "$1" == "GET" ]]; then
      printf '[]'
    else
      printf '%s' "$3" >"$marker"
      printf '{"id":"new1"}'
    fi
  }
  rp::args_parse --name n --size 10 --dc EU-RO-1 --type high_performance
  _volume_create >/dev/null 2>&1
  body="$(<"$marker")"
  assert_equals "HIGH_PERFORMANCE" "$(printf '%s' "$body" | jq -r '.type')"
  rp::http() { :; }
  rm -f "$marker"
}

function test_create_bad_type_exits_without_http() {
  local marker
  marker="$(mktemp)"
  rp::http() {
    printf 'POSTED' >>"$marker"
    printf '{"id":"x"}'
  }
  rp::args_parse --name n --size 10 --dc EU-RO-1 --type TURBO
  (_volume_create >/dev/null 2>&1)
  assert_exit_code 2
  assert_equals "" "$(cat "$marker")"
  rp::http() { :; }
  rm -f "$marker"
}

function test_should_show_help_when_help_flag_follows_verb() {
  local out
  out="$(rp::cmd_volume list --help 2>/dev/null)"
  assert_contains "Usage: rp volume" "$out"
}

# main-shell dispatcher call (bashunit skips lines run inside $(...)) so the
# public rp::cmd_volume entry registers coverage.
function test_should_show_help_when_help_verb_given_main_shell() {
  local tmp
  tmp="$(mktemp)"
  rp::cmd_volume help >"$tmp" 2>/dev/null
  assert_contains "Usage: rp volume" "$(<"$tmp")"
  rm -f "$tmp"
}

# Main-shell routing through the public dispatcher so each CRUD verb registers.
function test_should_route_each_volume_verb() {
  local cap
  cap="$(mktemp)"
  rp::http() {
    printf '%s %s\n' "$1" "$2" >"$cap"
    if [[ "$1" == "GET" ]]; then printf '[]'; else printf '{"id":"v1"}'; fi
  }
  rp::cmd_volume list >/dev/null 2>&1
  assert_contains "GET /network-volumes" "$(<"$cap")"
  rp::cmd_volume get v1 >/dev/null 2>&1
  assert_contains "GET /network-volumes/v1" "$(<"$cap")"
  rp::cmd_volume create --name n --size 5 --dc EU-RO-1 >/dev/null 2>&1
  assert_contains "POST /network-volumes" "$(<"$cap")"
  rp::cmd_volume update v1 --size 10 >/dev/null 2>&1
  assert_contains "PATCH /network-volumes/v1" "$(<"$cap")"
  rp::cmd_volume delete v1 >/dev/null 2>&1
  assert_contains "DELETE /network-volumes/v1" "$(<"$cap")"
  rm -f "$cap"
}

# Stub the volume lookup path: name -> id (vol1) and id -> datacenter (EU-RO-1,
# which sits in RP_S3_DCS_FALLBACK so rp::is_s3_dc passes offline).
_stub_volume_http() {
  rp::http() {
    case "$1 $2" in
    "GET /network-volumes") printf '{"networkVolumes":[{"id":"vol1","name":"myvol","dataCenter":"EU-RO-1"}]}' ;;
    "GET /network-volumes/vol1") printf '{"dataCenter":"EU-RO-1"}' ;;
    *) printf '{}' ;;
    esac
  }
}

# C6/B — `rp volume sync --source` drives the S3 seam: aws s3 sync must be called
# with the datacenter-derived --region and --endpoint-url and the volume-id bucket.
function test_volume_sync_source_invokes_aws_with_derived_endpoint() {
  local src
  src="$(mktemp -d)"
  : >"$src/file.txt"
  _stub_volume_http
  _aws_calls=()
  _hf_calls=()
  rp::cmd_volume sync myvol --source "$src" >/dev/null 2>&1
  assert_equals 1 "${#_aws_calls[@]}"
  assert_contains "s3 sync" "${_aws_calls[0]}"
  assert_contains "--region eu-ro-1" "${_aws_calls[0]}"
  assert_contains "--endpoint-url https://s3api-eu-ro-1.runpod.io/" "${_aws_calls[0]}"
  assert_contains "s3://vol1/models/" "${_aws_calls[0]}"
  assert_contains "--cli-read-timeout 7200" "${_aws_calls[0]}"
  rp::http() { :; }
  rm -rf "$src"
}

# C6/B — `rp volume ls` drives the S3 seam the same way (aws s3 ls, no timeout).
function test_volume_ls_invokes_aws_with_derived_endpoint() {
  _stub_volume_http
  _aws_calls=()
  _hf_calls=()
  rp::cmd_volume ls myvol --path models >/dev/null 2>&1
  assert_equals 1 "${#_aws_calls[@]}"
  assert_contains "s3 ls" "${_aws_calls[0]}"
  assert_contains "--region eu-ro-1" "${_aws_calls[0]}"
  assert_contains "--endpoint-url https://s3api-eu-ro-1.runpod.io/" "${_aws_calls[0]}"
  assert_contains "s3://vol1/models/" "${_aws_calls[0]}"
  rp::http() { :; }
}

# C6/B — `rp volume sync --models` fans out per model: huggingface-cli download
# (resolved repo + --local-dir) then aws s3 sync into s3://<id>/<prefix>/<model>/.
function test_volume_sync_models_invokes_huggingface_then_aws_per_model() {
  local cache
  cache="$(mktemp -d)"
  export RP_MODEL_CACHE="$cache"
  _stub_volume_http
  _aws_calls=()
  _hf_calls=()
  rp::cmd_volume sync myvol --models glm,flash >/dev/null 2>&1
  assert_equals 2 "${#_hf_calls[@]}"
  assert_contains "download zai-org/GLM-OCR --local-dir $cache/glm" "${_hf_calls[0]}"
  assert_contains "download infly/Infinity-Parser2-Flash --local-dir $cache/flash" "${_hf_calls[1]}"
  assert_equals 2 "${#_aws_calls[@]}"
  assert_contains "s3 sync" "${_aws_calls[0]}"
  assert_contains "s3://vol1/models/glm/" "${_aws_calls[0]}"
  assert_contains "s3://vol1/models/flash/" "${_aws_calls[1]}"
  assert_contains "--endpoint-url https://s3api-eu-ro-1.runpod.io/" "${_aws_calls[0]}"
  rp::http() { :; }
  rm -rf "$cache"
}
