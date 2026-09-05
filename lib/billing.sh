#!/usr/bin/env bash
# The billing time-window seam, shared by every verb that reports spend
# (rp billing's six GETs and rp cost-center spend). Validates the four window
# flags and hands back the ready-made query pairs; the caller appends them to
# its own REST path via rp::query_params. Kept off command substitution for
# the error paths — like the rp::require_* helpers, it assigns via nameref so
# a usage exit fires in the caller's shell even under errexit-off harnesses.
[[ -n "${_RP_BILLING_LIB:-}" ]] && return 0
_RP_BILLING_LIB=1

# Validate --start/--end/--bucket-size/--last-n (the flags shared by all
# billing reads) and assign the query pairs to the array nameref named in $1 —
# empty when no flag was given, otherwise ("startTime" v "endTime" v …) ready
# for rp::query_params. $2 prefixes usage errors with the calling command
# ("rp billing pods", "rp cost-center spend").
# Arguments:
#   $1 - out: caller's array name (nameref) to receive the query pairs
#   $2 - prefix: command name used in usage errors ("rp billing <verb>")
# Returns:
#   0 - pairs assigned to $1 (possibly empty)
#   2 - a window flag is malformed (rp::usage, in the caller's shell)
# Runs in the main shell, not via command substitution, so the rp::usage exit
# fires even when the caller has errexit off (mirrors rp::require_pos).
rp::billing_window_query() {
  local -n bwq_out="$1"
  local bwq_prefix="${2:-rp billing}"
  local bwq_start bwq_end bwq_bucket bwq_lastn
  bwq_start="$(rp::args_get start)"
  bwq_end="$(rp::args_get end)"
  bwq_bucket="$(rp::args_get bucket-size)"
  bwq_lastn="$(rp::args_get last-n)"
  # Validate in the caller's shell (not inside a command substitution) so a
  # non-integer --last-n exits 2 even under an errexit-off harness.
  rp::require_uint "$bwq_lastn" last-n

  # lastN is mutually exclusive with startTime/endTime (per spec).
  if [[ -n "$bwq_lastn" && (-n "$bwq_start" || -n "$bwq_end") ]]; then
    rp::usage "usage: $bwq_prefix --last-n is mutually exclusive with --start/--end"
  fi
  # lastN minimum is 1 (per spec); rp::require_uint only blocks non-numbers,
  # so 0 must be rejected here rather than in the shared helper (workers-min
  # and friends legitimately default to 0 elsewhere).
  if [[ -n "$bwq_lastn" && "$bwq_lastn" -lt "$RP_LAST_N_MIN" ]]; then
    rp::usage "usage: $bwq_prefix --last-n must be at least $RP_LAST_N_MIN"
  fi
  case "$bwq_bucket" in
  '' | hour | day | week | month | year) ;;
  *) rp::usage "usage: $bwq_prefix --bucket-size must be hour|day|week|month|year (got: '$bwq_bucket')" ;;
  esac

  bwq_out=()
  [[ -n "$bwq_start" ]] && bwq_out+=(startTime "$bwq_start")
  [[ -n "$bwq_end" ]] && bwq_out+=(endTime "$bwq_end")
  [[ -n "$bwq_bucket" ]] && bwq_out+=(bucketSize "$bwq_bucket")
  [[ -n "$bwq_lastn" ]] && bwq_out+=(lastN "$bwq_lastn")
}
