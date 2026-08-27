#!/usr/bin/env bash
# lib/update_check.sh — lazy, non-blocking "new rp version available" notice.
#
# The check runs with no network latency on the hot path: a fresh result is read
# from a cache under RP_CONFIG_HOME and printed immediately; a stale/missing
# cache triggers a short background fetch (GitHub releases/latest) that refreshes
# the cache for the NEXT invocation, so the user is told on the following command
# rather than paying a blocking curl on this one.
#
# Behaviour:
#   * skipped entirely when RP_NO_UPDATE_CHECK=1, when stderr is not a TTY
#     (scripts/CI/pipes), and for the self-referential commands (version,
#     upgrade, help, doc);
#   * skipped for dev/non-semver builds (e.g. "0.0.0-dev", `git describe`), so a
#     checkout never nags;
#   * the advice names the right upgrade path for the install method (bash
#     installer -> `rp upgrade`; npm -> `npm update -g runpod-cli`; brew ->
#     `brew upgrade runpod-cli`), detected from the resolved location of the `rp`
#     executable.
#
# Sourced by bin/rp; not executed directly.
# shellcheck source=common.sh
[[ -n "${_RP_UPDATE_CHECK:-}" ]] && return 0
_RP_UPDATE_CHECK=1

# Public entry: call once near the top of rp::main with the resource name ($1)
# so version/upgrade/help can be skipped. Never blocks, never dies.
rp::update_check() {
  [[ -z "${RP_NO_UPDATE_CHECK:-}" ]] || return 0
  # Only surface to a human terminal; never pollute script/CI/piped output.
  [[ -t 2 ]] || return 0
  case "${1:-}" in
  version | -v | --version | -h | --help | help | upgrade | doc) return 0 ;;
  esac
  local cache="$RP_CONFIG_HOME/.update-check"
  local now_ts
  now_ts="$(date +%s)"
  # Fast path: fresh cached result -> print now, no network.
  if [[ -f "$cache" ]]; then
    local cached_ts cached_latest
    cached_ts="$(jq -r '.checked // 0' "$cache" 2>/dev/null || echo 0)"
    cached_latest="$(jq -r '.latest // empty' "$cache" 2>/dev/null || true)"
    if ((now_ts - cached_ts < 86400)) && [[ -n "$cached_latest" ]]; then
      if rp::_version_is_behind "$cached_latest"; then
        rp::_print_update_notice "$cached_latest"
      fi
      return 0
    fi
  fi
  # Stale/missing: refresh in the background (guarded by a lock so concurrent
  # rp invocations don't each spawn a curl). No notice this run.
  local lock="$RP_CONFIG_HOME/.update-check.lock"
  if [[ -d "$lock" ]] && find "$lock" -maxdepth 0 -mmin +2 2>/dev/null | grep -q .; then
    rmdir "$lock" 2>/dev/null || true
  fi
  mkdir "$lock" 2>/dev/null || return 0
  # Double-fork + disown: fully detach the refresh so it survives `rp` exiting on
  # a fast command (the parent must not block waiting for it). A stale lock older
  # than 2 min is recycled above, so a killed refresh self-heals.
  ( (rp::_update_check_refresh "$cache" "$lock") </dev/null >/dev/null 2>&1 &)
  disown 2>/dev/null || true
  return 0
}

# Background worker: fetch the latest GitHub release tag and write the cache
# atomically. Runs without an API key (GitHub's public releases endpoint needs
# none). Removes the lock on the way out.
rp::_update_check_refresh() {
  local cache="$1" lock="$2" url tmp status latest tmpc
  url="https://api.github.com/repos/${RP_UPGRADE_REPO}/releases/latest"
  _mktemp tmp
  status="$(curl -fsSL --connect-timeout 2 --max-time 5 \
    -H 'Accept: application/vnd.github+json' \
    -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null)" || status=000
  if [[ "$status" == 2* ]]; then
    latest="$(jq -r '.tag_name // empty' "$tmp" 2>/dev/null | sed 's/^v//')"
    if [[ -n "$latest" ]]; then
      _mktemp tmpc
      jq -nc --arg ts "$(date +%s)" --arg l "$latest" \
        '{checked: ($ts | tonumber), latest: $l}' >"$tmpc"
      mv -f "$tmpc" "$cache"
    fi
  fi
  rm -f "$tmp"
  rmdir "$lock" 2>/dev/null || true
}

# True (0) iff the installed version is a plain semver strictly older than $1.
rp::_version_is_behind() {
  local latest="$1" cur
  cur="$(rp::version)"
  [[ "$cur" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  [[ "$latest" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  local i n m max
  local -a c l
  IFS=. read -ra c <<<"$cur"
  IFS=. read -ra l <<<"$latest"
  n=${#c[@]}
  m=${#l[@]}
  max=$n
  ((m > max)) && max=$m
  for ((i = 0; i < max; i++)); do
    local cv="${c[i]:-0}" lv="${l[i]:-0}"
    ((cv < lv)) && return 0
    ((cv > lv)) && return 1
  done
  return 1
}

# Resolve a (possibly chained) symlink to its final target, portably — macOS's
# readlink lacks -f, so follow the chain in a loop like bin/rp does.
rp::_resolve() {
  local p="$1" dir
  while [[ -L "$p" ]]; do
    dir="${p%/*}"
    p="$(readlink "$p" 2>/dev/null || true)"
    [[ -n "$p" && "$p" != /* ]] && p="$dir/$p"
  done
  printf '%s' "$p"
}

# How rp was installed, from the resolved location of the `rp` executable.
rp::_detect_install_method() {
  local p resolved
  p="$(command -v rp 2>/dev/null)"
  [[ -n "$p" ]] || {
    printf '%s' unknown
    return
  }
  resolved="$(rp::_resolve "$p")"
  [[ -n "$resolved" ]] || resolved="$p"
  case "$resolved" in
  *homebrew* | *Cellar*) printf '%s' brew ;;
  *node_modules* | *npm* | *npx* | *lib/node*) printf '%s' npm ;;
  *"$HOME/.rp"* | */.rp/*) printf '%s' bash ;;
  *) printf '%s' unknown ;;
  esac
}

# Emit the one-line notice, naming the install-appropriate upgrade command.
rp::_print_update_notice() {
  local latest="$1" cur advice method
  cur="$(rp::version)"
  method="$(rp::_detect_install_method)"
  case "$method" in
  npm) advice="run 'npm update -g runpod-cli'" ;;
  brew) advice="run 'brew upgrade runpod-cli'" ;;
  bash) advice="run 'rp upgrade'" ;;
  *) advice="run 'rp upgrade' (or reinstall via your package manager)" ;;
  esac
  rp::warn "rp $latest available (you have $cur) — $advice"
}
