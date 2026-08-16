#!/usr/bin/env bash
# install.sh — one-line installer for rp (RunPod CLI).
#
#   curl -fsSL https://raw.githubusercontent.com/objctp/runpod-cli/main/install.sh | bash
#
# Bash 3.2-safe on purpose. macOS pipes this to /bin/bash (3.2), so the script
# must run under it long enough to print the "rp needs Bash 5+" error: no
# associative arrays, no mapfile/readarray, no ${var,,}. rp itself needs Bash 5+,
# so on macOS we detect an older bash and refuse rather than install something
# that won't run. rp is plain bash, so there is one universal tarball — no
# per-OS/arch matrix.
set -euo pipefail

# OWNER/REPO that hosts releases and this script. Change here (and in
# commands/upgrade.sh) if the canonical repo moves.
RP_REPO="objctp/runpod-cli"
RP_INSTALL_DIR="${RP_INSTALL_DIR:-$HOME/.rp}"
RP_BINDIR="${RP_BINDIR:-/usr/local/bin}"

# Temp dir for the install flow. Global (not local to rp_inst_run) so the EXIT
# trap can rm it after the function returns — a `local` would be out of scope by
# then, leaving the temp dir behind and tripping `set -u` in the trap.
_rp_inst_tmp=""

if [[ -t 1 ]]; then
  _C_RED=$'\033[31m'
  _C_GRN=$'\033[32m'
  _C_YEL=$'\033[33m'
  _C_RST=$'\033[0m'
else
  _C_RED=""
  _C_GRN=""
  _C_YEL=""
  _C_RST=""
fi

rp_inst_info() { printf '%s\n' "$*" >&2; }
rp_inst_warn() { printf '%s%s%s\n' "$_C_YEL" "$*" "$_C_RST" >&2; }
rp_inst_ok() { printf '%s%s%s\n' "$_C_GRN" "$*" "$_C_RST" >&2; }
rp_inst_err() { printf '%s%s%s\n' "$_C_RED" "$*" "$_C_RST" >&2; }
rp_inst_die() {
  rp_inst_err "$*"
  exit 1
}

###
### :::: probes :::: ###################
###
# Each probe reads an override env var so the installer is testable.

# Echo darwin/linux; return 1 on anything else.
rp_inst_os() {
  local u="${RP_UNAME:-$(uname -s)}"
  case "$u" in
  Darwin) echo darwin ;;
  Linux) echo linux ;;
  *) return 1 ;;
  esac
}

# Return 0 if the running bash is major >= 5 (rp's requirement). RP_BASH_MAJOR
# lets tests simulate macOS's 3.2 without a readonly BASH_VERSINFO override.
rp_inst_bash_ok() {
  local major="${RP_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}}"
  [[ "$major" -ge 5 ]]
}

# Reject a version/Tag that does not look like a release. A crafted or
# typo'd value would otherwise be interpolated into the GitHub release URL and,
# after curl's path-normalisation, could redirect the download to an
# attacker-controlled repo. Only x.y.z (with an optional leading v) is accepted.
rp_inst_validate_version() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    rp_inst_die "invalid version '$1' — expected x.y.z or vX.Y.Z (e.g. 1.2.3)"
}

# Echo the release tag to install. RP_LATEST_TAG short-circuits the network
# lookup for tests; otherwise GitHub's /releases/latest 302-redirects to
# /releases/tag/<tag>, and following it to the final URL needs no jq and dodges
# the rate-limited REST API. The resolved tag is validated before use so a
# hostile/malformed redirect cannot steer the install elsewhere.
rp_inst_resolve_version() {
  local tag
  if [[ -n "${RP_LATEST_TAG:-}" ]]; then
    tag="$RP_LATEST_TAG"
  else
    local url
    url="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
      "https://github.com/$RP_REPO/releases/latest")" ||
      rp_inst_die "could not reach github.com/$RP_REPO (network down, or no releases published yet)"
    tag="${url##*/}"
  fi
  rp_inst_validate_version "$tag"
  printf '%s\n' "$tag"
}

# Constrain the RP_CHECKSUM override to an allowlist. The value is later
# word-split into argv and executed, so accepting an arbitrary string would let
# anyone who can set the env var inject commands (e.g. "shasum -a 256; rm -rf ~").
# Only the two known-safe checkers are permitted; anything else is rejected.
rp_inst_validate_checksum() {
  [[ -z "${RP_CHECKSUM:-}" ]] && return 0
  case "$RP_CHECKSUM" in
  sha256sum | "shasum -a 256") return 0 ;;
  *)
    rp_inst_die "RP_CHECKSUM must be exactly 'sha256sum' or 'shasum -a 256' (got: '$RP_CHECKSUM')"
    ;;
  esac
}

# Return 0 (unsafe) for a tar member name that is absolute or escapes the
# extraction root via `..` — `tar -xzf` would otherwise write outside $stage.
# The checksum gate already anchors integrity; this is defense-in-depth for the
# one place untrusted bytes are unpacked.
rp_inst_member_is_unsafe() {
  [[ "$1" == /* ]] || [[ "$1" == *"/../"* ]] || [[ "$1" == "../"* ]] || [[ "$1" == ".." ]]
}

# Echo the SHA-256 verifying command as a string ("sha256sum" or "shasum -a 256"),
# or return 1 if neither tool exists. RP_CHECKSUM overrides for tests (validated
# by rp_inst_validate_checksum before this runs).
rp_inst_checksum_cmd() {
  if [[ -n "${RP_CHECKSUM:-}" ]]; then
    printf '%s\n' "$RP_CHECKSUM"
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256sum\n'
  elif command -v shasum >/dev/null 2>&1; then
    printf 'shasum -a 256\n'
  else
    return 1
  fi
}

rp_inst_download_url() {
  printf 'https://github.com/%s/releases/download/%s/rp-%s.tar.gz\n' "$RP_REPO" "$1" "$1"
}

rp_inst_checksum_url() {
  printf 'https://github.com/%s/releases/download/%s/SHA256SUMS\n' "$RP_REPO" "$1"
}

# Return 0 if $1 is a directory on $PATH. The optional $2 is a colon-separated
# search list (defaults to $PATH) so tests can pass it explicitly instead of
# mutating the global $PATH.
rp_inst_on_path() {
  local dir="$1" search="${2:-${PATH:-}}" parts=()
  local d
  IFS=: read -ra parts <<<"$search"
  for d in "${parts[@]}"; do
    [[ "$d" == "$dir" ]] && return 0
  done
  return 1
}

# If $1 is not on $PATH, append an export line to the matching shell rc and echo
# its path. No-op (and no output) if $1 is already on $PATH, or if the export is
# already present. For system-wide installs /usr/local/bin is virtually always on
# PATH already, so this rarely fires — it exists for unusual setups.
rp_inst_ensure_path() {
  local dir="$1" rc line shell
  # A bindir with whitespace would break the quoted export line below and any
  # later PATH split; the value is user-controllable (RP_BINDIR), so refuse it
  # rather than emit a malformed rc entry.
  [[ -z "$dir" ]] && return 1
  [[ "$dir" == *[[:space:]]* ]] && {
    rp_inst_warn "not adding '$dir' to PATH: it contains whitespace; add it to your shell rc manually"
    return 1
  }
  rp_inst_on_path "$dir" && return 0
  shell="$(basename "${SHELL:-bash}")"
  case "$shell" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
  *) rc="$HOME/.profile" ;;
  esac
  line="export PATH=\"$dir:\$PATH\""
  if [[ -f "$rc" ]] && grep -qF "$line" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "# added by rp installer"
    echo "$line"
  } >>"$rc"
  printf '%s\n' "$rc"
}

###
### :::: install flow :::: #############
###

rp_inst_run() {
  local version=""
  while (($#)); do
    case "$1" in
    --version)
      shift
      (($#)) || rp_inst_die "--version needs a value"
      version="$1"
      shift
      ;;
    --version=*)
      version="${1#*=}"
      shift
      ;;
    --help | -h)
      rp_inst_info "Usage: curl -fsSL .../install.sh | bash [--version x.y.z]"
      rp_inst_info "Env: RP_INSTALL_DIR (~/.rp), RP_BINDIR (/usr/local/bin)"
      exit 0
      ;;
    *)
      rp_inst_die "unknown option: $1 (try --help)"
      ;;
    esac
  done

  command -v curl >/dev/null 2>&1 || rp_inst_die "curl is required to install rp"
  command -v tar >/dev/null 2>&1 || rp_inst_die "tar is required to install rp"

  # An explicit --version is validated up front; a resolved-latest tag is
  # validated inside rp_inst_resolve_version. Either way we never reach the
  # download with an unvalidated version.
  [[ -n "$version" ]] && rp_inst_validate_version "$version"

  # Constrain the checksum override before it is word-split into argv.
  rp_inst_validate_checksum

  local os
  os="$(rp_inst_os)" ||
    rp_inst_die "unsupported OS: $(uname -s) (rp supports macOS and Linux)"

  if [[ "$os" == "darwin" ]] && ! rp_inst_bash_ok; then
    rp_inst_die "rp needs Bash 5+; this macOS has $(printf '%s.%s' \
      "${BASH_VERSINFO[0]:-?}" "${BASH_VERSINFO[1]:-?}"). Fix: brew install bash, \
 then restart your shell and re-run the installer."
  fi

  [[ -n "$version" ]] || version="$(rp_inst_resolve_version)"
  rp_inst_info "Installing rp $version from $RP_REPO"

  _rp_inst_tmp="$(mktemp -d)"
  local sums_file="$_rp_inst_tmp/SHA256SUMS"
  local tarball="$_rp_inst_tmp/rp-$version.tar.gz"
  # stage/ lives under _rp_inst_tmp so the EXIT trap cleans everything in one place.
  trap 'rm -rf "$_rp_inst_tmp"' EXIT

  # Create the install tree under a restrictive umask so ~/.rp and its contents
  # never inherit a loose umask (e.g. 000) from the caller's environment.
  umask 022

  curl -fsSL -o "$tarball" "$(rp_inst_download_url "$version")" ||
    rp_inst_die "download failed: $(rp_inst_download_url "$version")"
  curl -fsSL -o "$sums_file" "$(rp_inst_checksum_url "$version")" ||
    rp_inst_die "checksum file download failed"

  local ck_str
  ck_str="$(rp_inst_checksum_cmd)" ||
    rp_inst_die "need 'sha256sum' or 'shasum' to verify the download"
  # shellcheck disable=SC2206 # split a trusted internal string into argv
  local -a ck=(${ck_str})
  (cd "$_rp_inst_tmp" && "${ck[@]}" -c SHA256SUMS >/dev/null 2>&1) ||
    rp_inst_die "checksum mismatch — the download was corrupted or tampered with; aborting"

  # Extract into a staging dir, then swap into RP_INSTALL_DIR (back up the old
  # tree first so a failure rolls back instead of leaving a half-installed CLI).
  local stage="$_rp_inst_tmp/stage"
  mkdir -p "$stage"
  # Refuse a tarball whose members are absolute or escape via `..` before
  # extracting — defense-in-depth on top of the checksum gate. A `tar -tzf`
  # failure (corrupt/empty artefact) also aborts rather than silently no-op.
  local _members _m
  _members="$(tar -tzf "$tarball" 2>/dev/null)" ||
    rp_inst_die "could not read tarball contents; refusing to extract"
  while IFS= read -r _m; do
    rp_inst_member_is_unsafe "$_m" &&
      rp_inst_die "tarball contains an unsafe path; refusing to extract"
  done <<<"$_members"
  # --no-same-owner: don't try to reproduce the tarball's ownership (which may
  # not exist locally); extract as the invoking user. Prevents permission errors
  # and any adversary-controlled ownership in a compromised release artefact.
  tar -xzf "$tarball" -C "$stage" --no-same-owner || rp_inst_die "extraction failed"

  # Guard against wiping an unrelated directory. RP_INSTALL_DIR defaults to
  # ~/.rp, but if a user points it at e.g. $HOME we must not `mv` the whole tree
  # away. Only proceed when it does not exist, is empty, or is a recognised rp
  # install (contains bin/rp). Otherwise refuse rather than move/overwrite it.
  local backup=""
  if [[ -e "$RP_INSTALL_DIR" ]]; then
    if [[ -n "$(find "$RP_INSTALL_DIR" -maxdepth 0 -type d -empty 2>/dev/null)" ]]; then
      : # empty directory — safe to back up and replace
    elif [[ -e "$RP_INSTALL_DIR/bin/rp" ]]; then
      : # existing rp install — safe to upgrade in place
    else
      rp_inst_die "$RP_INSTALL_DIR exists, is non-empty, and is not an rp install (no bin/rp); refusing to overwrite it"
    fi
    backup="$RP_INSTALL_DIR.old.$$"
    mv "$RP_INSTALL_DIR" "$backup"
  fi
  mkdir -p "$RP_INSTALL_DIR"
  if ! mv "$stage"/* "$RP_INSTALL_DIR"/ 2>/dev/null; then
    [[ -n "$backup" ]] && {
      rm -rf "$RP_INSTALL_DIR"
      mv "$backup" "$RP_INSTALL_DIR"
    }
    rp_inst_die "failed to place files into $RP_INSTALL_DIR"
  fi
  [[ -n "$backup" ]] && rm -rf "$backup"

  # System-wide symlink /usr/local/bin/rp -> RP_INSTALL_DIR/bin/rp. Use sudo only
  # for this one link (and only if /usr/local/bin isn't user-writable).
  local target="$RP_INSTALL_DIR/bin/rp"
  [[ -x "$target" ]] || rp_inst_die "installed rp binary not executable: $target"
  if [[ -w "$RP_BINDIR" ]]; then
    ln -sfn "$target" "$RP_BINDIR/rp"
  elif command -v sudo >/dev/null 2>&1; then
    rp_inst_warn "$RP_BINDIR is not writable — creating the symlink with sudo"
    sudo ln -sfn "$target" "$RP_BINDIR/rp"
  else
    rp_inst_warn "cannot write $RP_BINDIR and sudo is unavailable; create the link yourself:"
    rp_inst_warn "  sudo ln -sf $target $RP_BINDIR/rp"
    rp_inst_warn "(or add $RP_INSTALL_DIR/bin to your PATH)"
  fi

  # Ensure the executable directory is reachable; touch a shell rc only if it
  # genuinely isn't on PATH yet (almost always a no-op for /usr/local/bin).
  local rc
  rc="$(rp_inst_ensure_path "$RP_BINDIR" 2>/dev/null || true)"
  if [[ -n "$rc" ]]; then
    rp_inst_warn "added $RP_BINDIR to PATH via $rc — open a new shell or run: source $rc"
  fi

  rp_inst_ok "Installed rp $version -> $RP_BINDIR/rp"
  rp_inst_info "  source:  $RP_INSTALL_DIR"
  rp_inst_info "  verify:  rp version"
  rp_inst_info "  next:    set RUNPOD_API_KEY (see https://github.com/$RP_REPO#readme)"
}

# Run only when executed directly, so unit tests can source the functions above.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  rp_inst_run "$@"
fi
