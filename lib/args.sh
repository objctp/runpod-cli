#!/usr/bin/env bash
# Flag and positional parser. Every command calls rp::args_parse, then reads values via rp::args_get / _has / _pos / _get_uint / rp::require_pos.
[[ -n "${_RP_ARGS:-}" ]] && return 0
_RP_ARGS=1

declare -gA RP_ARGS=()
# All positional arguments in order (RP_ARGS[pos] is a backward-compat alias for
# the first). A handful of verbs (e.g. `rp serverless status <id> <jobId>`) take
# more than one positional; read the rest via rp::args_pos_at / rp::require_pos_at.
declare -ga RP_POSITIONALS=()
RP_BOOL_FLAGS=(async json flashboot force help interruptible serverless sync ssh)
# Value flags that may be repeated; occurrences accumulate newline-joined, so
# `--env A=1 --env B=2` becomes "A=1\nB=2". Newline (not comma) is the separator
# so a single value may itself contain commas (e.g. --env LIST=a,b). Add a flag
# name here to make it repeatable; consumers iterate the joined value by line
# (rp::env_to_json).
RP_REPEAT_FLAGS=(env)

_args_is_repeatable() {
  [[ " ${RP_REPEAT_FLAGS[*]} " == *" $1 "* ]]
}

rp::args_parse() {
  RP_ARGS=()
  local k
  while (($#)); do
    case "$1" in
    --help | -h)
      RP_ARGS[help]=1
      shift
      ;;
    --*=*)
      k="${1%%=*}"
      k="${k#--}"
      if _args_is_repeatable "$k"; then
        RP_ARGS["$k"]="${RP_ARGS[$k]:+${RP_ARGS[$k]}$'\n'}${1#*=}"
      else
        RP_ARGS["$k"]="${1#*=}"
      fi
      shift
      ;;
    --*)
      k="${1#--}"
      shift
      if [[ " ${RP_BOOL_FLAGS[*]} " == *" $k "* ]]; then
        RP_ARGS["$k"]=1
      elif _args_is_repeatable "$k"; then
        (($#)) || rp::usage "flag --$k requires a value"
        RP_ARGS["$k"]="${RP_ARGS[$k]:+${RP_ARGS[$k]}$'\n'}$1"
        shift
      else
        (($#)) || rp::usage "flag --$k requires a value"
        RP_ARGS["$k"]="$1"
        shift
      fi
      ;;
    *)
      # Collect every positional in order; RP_ARGS[pos] stays the first for the
      # many verbs that take exactly one id (e.g. `rp pod get <id>`). Verbs that
      # need more read the rest via rp::args_pos_at / rp::require_pos_at.
      RP_POSITIONALS+=("$1")
      [[ -n "${RP_ARGS[pos]:-}" ]] || RP_ARGS[pos]="$1"
      shift
      ;;
    esac
  done
  rp::args_apply_aliases
}

rp::args_get() { printf '%s' "${RP_ARGS[$1]:-${2:-}}"; }

rp::args_has() { [[ -n "${RP_ARGS[$1]:-}" ]]; }

rp::args_pos() { printf '%s' "${RP_ARGS[pos]:-}"; }

# Print the positional at index $1 (0-based). Defaults to the first when $1 is
# empty. Used by verbs with more than one positional (e.g.
# `rp serverless status <id> <jobId>`).
rp::args_pos_at() {
  local idx="${1:-0}"
  printf '%s' "${RP_POSITIONALS[$idx]:-}"
}

# Assign the positional to the variable named in $1.
# Arguments:
#   $1 - out: caller's variable name (nameref) to receive the positional
#   $2 - usage: message shown when none was given
# Returns:
#   0 - positional assigned to $1
#   1 - no positional given (rp::usage)
# Runs in the main shell, not via command substitution, so the exit fires even
# when the caller has errexit off.
rp::require_pos() {
  local -n require_pos_out="$1"
  [[ -n "${RP_ARGS[pos]:-}" ]] || rp::usage "$2"
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  require_pos_out="${RP_ARGS[pos]}"
}

# Like rp::require_pos but for the positional at index $1 (0-based). Lets a verb
# demand a specific positional beyond the first (e.g. the job id in
# `rp serverless status <id> <jobId>`).
# Arguments:
#   $1 - index: 0-based positional index
#   $2 - out: caller's variable name (nameref) to receive the positional
#   $3 - usage: message shown when the positional is missing
rp::require_pos_at() {
  local idx="${1:-0}"
  local -n require_pos_at_out="$2"
  [[ -n "${RP_POSITIONALS[$idx]:-}" ]] || rp::usage "$3"
  # shellcheck disable=SC2034 # nameref assignment lands in the caller's variable
  require_pos_at_out="${RP_POSITIONALS[$idx]}"
}

# rp::args_get that rp::die's unless the value is a non-negative integer (or unset).
rp::args_get_uint() {
  local val
  val="$(rp::args_get "$1" "${2:-}")"
  rp::require_uint "$val" "$1"
  printf '%s' "$val"
}

# Assign the true|false value of --$2 to the variable named by $1 (nameref);
# empty when the flag is unset, rp::usage on any other token. For value flags
# that must carry both directions (--public, --locked, --global-networking) so
# update can DISABLE as well as enable — a bare bool flag can only express true.
# Call DIRECTLY, never inside command substitution: rp::usage's exit must fire in
# the caller's shell, and tests run with errexit off (so `v="$(rp::… F)"` would
# swallow a bad token). Mirrors rp::require_pos.
rp::require_bool() {
  local -n require_bool_out="$1"
  require_bool_out="$(rp::args_get "$2" "${3:-}")"
  case "$require_bool_out" in
  '') ;;
  true | false) ;;
  *) rp::usage "invalid --$2 '$require_bool_out' (expected true|false)" ;;
  esac
}

rp::split_csv() {
  local -a arr
  IFS=, read -ra arr <<<"$1"
  printf '%s\n' "${arr[@]}"
}

# Post-parse flag aliases: runpodctl spelling -> rp canonical (key-copy only).
# Never overloads an rp flag, and never overwrites an explicitly-set canonical
# value. --env is deliberately NOT aliased: rp uses repeatable K=V
# (RP_REPEAT_FLAGS), runpodctl a single JSON object — divergent shapes.
RP_FLAG_ALIASES=(
  "gpu-id:gpu"
  "data-center-ids:dc"
  "container-disk-in-gb:container-disk-gb"
  "volume-in-gb:volume-gb"
  "volume-mount-path:volume-path"
  "registry-auth-id:registry"
  "cloud-type:cloud"
  "docker-args:start-cmd"
  "docker-start-cmd:docker-cmd"
)

# An alias whose name already means something in rp (a known bool/repeat flag)
# is skipped — rp's meaning always wins, never overloaded.
# Returns 0 (free) when $1 is not a known bool/repeat flag, 1 otherwise.
rp::args_alias_is_free() {
  [[ " ${RP_BOOL_FLAGS[*]} ${RP_REPEAT_FLAGS[*]} " != *" $1 "* ]]
}

# Apply RP_FLAG_ALIASES once after parsing: copy each alias into its canonical
# when the canonical is absent. Called from rp::args_parse; the tokenizer above
# is untouched.
rp::args_apply_aliases() {
  local entry alias canonical
  for entry in "${RP_FLAG_ALIASES[@]}"; do
    alias="${entry%%:*}"
    canonical="${entry##*:}"
    rp::args_alias_is_free "$alias" || continue
    if [[ -z "${RP_ARGS[$canonical]:-}" && -n "${RP_ARGS[$alias]:-}" ]]; then
      RP_ARGS["$canonical"]="${RP_ARGS[$alias]}"
    fi
  done
}
