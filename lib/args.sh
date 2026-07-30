#!/usr/bin/env bash
# Flag and positional parser. Every command calls rp::args_parse, then reads values via rp::args_get / _has / _pos / _get_uint / rp::require_pos.
[[ -n "${_RP_ARGS:-}" ]] && return 0
_RP_ARGS=1

declare -gA RP_ARGS=()
RP_BOOL_FLAGS=(async json flashboot force help interruptible serverless sync)
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
      # Keep only the first positional; every rp command takes at most one, so
      # ignoring extras avoids "rp pod get a b" -> id "a b" -> a malformed URL.
      [[ -n "${RP_ARGS[pos]:-}" ]] || RP_ARGS[pos]="$1"
      shift
      ;;
    esac
  done
}

rp::args_get() { printf '%s' "${RP_ARGS[$1]:-${2:-}}"; }

rp::args_has() { [[ -n "${RP_ARGS[$1]:-}" ]]; }

rp::args_pos() { printf '%s' "${RP_ARGS[pos]:-}"; }

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

# rp::args_get that rp::die's unless the value is a non-negative integer (or unset).
rp::args_get_uint() {
  local val
  val="$(rp::args_get "$1" "${2:-}")"
  rp::require_uint "$val" "$1"
  printf '%s' "$val"
}

rp::split_csv() {
  local -a arr
  IFS=, read -ra arr <<<"$1"
  printf '%s\n' "${arr[@]}"
}
