#!/usr/bin/env bash
# Completion grammar spec — `rp _complete-spec` prints the CLI grammar as
# prefix-tagged TSV for the completion generator (a later phase — nothing
# sources it yet). The comment-based doc blocks parsed by lib/doc.sh are the
# single source of truth: no flag list is duplicated here.
# Records (TAB-separated):
#   v<TAB>resource<TAB>verb            verb exists (sub-verbs as "group sub")
#   u<TAB>resource<TAB>verb<TAB>usage  one-line usage synopsis
#   f<TAB>resource<TAB>verb<TAB>flag<TAB>kind<TAB>token<TAB>description
#                                      flag record; kind is bool|value; token
#                                      is the value placeholder (`<type>`,
#                                      `SECURE|COMMUNITY`, `N`) — empty for
#                                      bools; the generator splits `|`-bearing
#                                      tokens into static enum candidates
# Globals carry resource/verb "*" — the generator decides where they surface.
[[ -n "${_RP_COMPLETION:-}" ]] && return 0
_RP_COMPLETION=1

# Flags accepted by (almost) every verb regardless of per-verb doc coverage.
_RP_COMPLETION_GLOBALS=(
  "json:bool:print raw JSON instead of a table"
  "jq:value:jq filter applied to the response"
  "limit:value:return at most N records"
  "cursor:value:page offset to resume from"
  "insecure:bool:skip TLS certificate verification (-k)"
  "help:bool:show help"
)

# Squeeze runs of whitespace in the variable named $1 into $2 (namerefs, so no
# subshell fork — a $() per record cost ~350 forks across the full spec).
# Word splitting IS the squeeze.
# shellcheck disable=SC2086
_rp_completion_squeeze() {
  local -n _sq_in="$1"
  local -n _sq_out="$2"
  local _sq_w
  _sq_out=""
  for _sq_w in ${_sq_in}; do _sq_out+="$_sq_w "; done
  _sq_out="${_sq_out% }"
}

# Emit the f record for the flag being accumulated and reset the accumulator.
# Reads the caller's res/verb/cur_* locals (bash dynamic scoping — the parser
# and this flusher are one unit, same convention as lib/resource.sh's
# callback-into-caller-locals notes).
_rp_completion_flush() {
  if [[ -n "${cur_flag:-}" ]]; then
    _rp_completion_squeeze cur_desc desc
    printf 'f\t%s\t%s\t%s\t%s\t%s\t%s\n' "$res" "$verb" "$cur_flag" "$cur_kind" "$cur_token" "$desc"
  fi
  cur_flag=""
  cur_token=""
}

# Parse one verb's marker-stripped doc block (stdin) into u/f records.
# Layout convention relied upon (see any commands/*.sh Options section):
#   - Options rows start at exactly two spaces; the description follows a
#     two-plus-space gap; an optional single value token sits between
#     (`--gpu <type>  desc` -> value, `--ssh   desc` -> bool).
#   - Wrapped description continuations are indented deeper (4+ spaces).
#   - Blank lines and zero-indent lines (`Notes:`, `API:`…) end the section.
_rp_completion_parse_block() {
  local res="$1" verb="$2" line indent trimmed rest
  local usage="" usage_open="" in_opts=0
  local cur_flag="" cur_kind="" cur_token="" cur_desc=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^( +) ]]; then indent=${#BASH_REMATCH[1]}; else indent=0; fi
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if ((in_opts)); then
      if [[ -z "$trimmed" ]] || ((indent == 0)); then
        _rp_completion_flush
        in_opts=0
        continue
      fi
      # A flag row starts at the two-space Options indent. Deep-indented
      # lines that begin with `--` are wrapped descriptions mentioning
      # another flag (e.g. "… (alias: --gpu-id)") — continuations, not rows.
      if [[ "$trimmed" == --* ]] && ((indent == 2)); then
        _rp_completion_flush
        # Split the row procedurally: flag word, then either a two-plus-space
        # gap (bool) or a single-space-separated value token. The gap rule
        # cannot be one regex: when flag+value spans past the description
        # column the description collapses to ONE space
        # (`--global-networking true|false give the pod …`), which would make
        # `give` read as the value token.
        if [[ "$line" =~ ^[[:space:]]+(--[a-z0-9][a-z0-9-]*)(.*)$ ]]; then
          cur_flag="${BASH_REMATCH[1]#--}"
          cur_token=""
          rest="${BASH_REMATCH[2]}"
          if [[ "$rest" == "  "* ]]; then
            cur_kind=bool
            cur_desc="${rest#"${rest%%[![:space:]]*}"}"
          else
            cur_kind=value
            rest="${rest# }"
            cur_token="${rest%% *}"
            cur_desc=""
            if [[ "$rest" == *" "* ]]; then
              cur_desc="${rest#* }"
            fi
            # A trailing row with nothing after the token is a misaligned
            # bool, not a value flag — never advertise an empty value token.
            [[ -n "$cur_token" ]] || cur_kind=bool
          fi
        fi
        continue
      fi
      if ((indent >= 4)) && [[ -n "$cur_flag" ]]; then
        cur_desc+=" $trimmed"
        continue
      fi
      _rp_completion_flush
      in_opts=0
      continue
    fi
    if [[ -n "$usage_open" ]]; then
      if ((indent > 0)) && [[ -n "$trimmed" ]]; then
        usage+=" $trimmed"
        continue
      fi
      usage_open=""
    fi
    case "$trimmed" in
    "Usage: "*)
      usage="${trimmed#Usage: }"
      usage_open=1
      ;;
    "Options:") in_opts=1 ;;
    esac
  done
  _rp_completion_flush
  if [[ -n "$usage" ]]; then
    _rp_completion_squeeze usage usage_sq
    # shellcheck disable=SC2154 # nameref assignment lands in the caller's variable
    printf 'u\t%s\t%s\t%s\n' "$res" "$verb" "$usage_sq"
  fi
  return 0
}

# Emit all records for one command module: verbs from the case-arm index
# (lib/doc.sh), then each verb's block, then the group verb's sub-verbs
# (markers are multi-word: `delegations list`).
# $3 is a scratch file path (from rp::completion_spec, cleanup-tracked).
# Everything runs IN-PROCESS with stdout redirected to the scratch file: the
# doc index caches per process, and a `$( )`/pipe would push each doc call
# into a subshell that re-reads and re-indexes the whole command file — the
# full spec cost ~30 s that way; in-process it costs a couple of seconds —
# fine for the generator, which is why the TAB keystroke will not call this
# verb (the dynamic value completion of a later phase reads state directly).
_rp_completion_resource() {
  local file="$1" res="$2" tmp="$3" verb
  local -a subs=()
  rp::doc_verbs "$file" >"$tmp"
  local -a verbs=()
  mapfile -t verbs <"$tmp"
  for verb in "${verbs[@]}"; do
    [[ -n "$verb" ]] || continue
    printf 'v\t%s\t%s\n' "$res" "$verb"
    rp::doc_verb_marker "$file" "$verb" >"$tmp"
    _rp_completion_parse_block "$res" "$verb" <"$tmp"
    rp::doc_subverbs "$file" "$verb" >"$tmp"
    mapfile -t subs <"$tmp"
    local sub
    for sub in "${subs[@]}"; do
      [[ -n "$sub" ]] || continue
      printf 'v\t%s\t%s %s\n' "$res" "$verb" "$sub"
      rp::doc_verb_marker "$file" "$verb $sub" >"$tmp"
      _rp_completion_parse_block "$res" "$verb $sub" <"$tmp"
    done
    subs=()
  done
  return 0
}

# The whole grammar, one TSV record per line. No network, no state — safe to
# call from the completion generator and from a TAB keystroke alike.
rp::completion_spec() {
  local file res entry name kind desc tmp
  _mktemp tmp
  for file in "$RP_ROOT"/commands/*.sh; do
    res="${file##*/}"
    res="${res%.sh}"
    _rp_completion_resource "$file" "$res" "$tmp"
  done
  for entry in "${_RP_COMPLETION_GLOBALS[@]}"; do
    name="${entry%%:*}"
    kind="${entry#*:}"
    kind="${kind%%:*}"
    desc="${entry#*:*:}"
    printf 'f\t*\t*\t%s\t%s\t%s\t%s\n' "$name" "$kind" "" "$desc"
  done
  return 0
}

###
### :::: dynamic value completion (`rp _complete`) :::: ###################
###

# TAB time never waits on the network once a cache exists: local state
# (cost centers, accounts) answers directly; resource ids/names are served
# from a TTL cache under $RP_CONFIG_HOME/completion/ — stale caches print
# immediately and refresh in the background, and only a cold cache pays one
# synchronous fetch. RP_COMPLETION_SYNC_REFRESH=1 forces the refresh
# foreground (tests).
_RP_COMPLETE_TTL=300

# Print candidates for one completion position.
# Arguments:
#   $1 - resource (pod, volume, serverless, auth, cost-center, …)
#   $2 - verb, as typed (may carry the group: "delegations list")
#   $3 - target: a flag name without "--", or "-" for the first positional
rp::complete() {
  local res="$1" verb="$2" target="$3"
  case "$target" in
  cost-center) rp::cc_names ;;
  -) rp::complete_positional "$res" ;;
  esac
  # Unknown flag/position: print nothing, exit 0 — completion stays silent.
  return 0
}

rp::complete_positional() { # $1 resource
  local f
  case "$1" in
  auth)
    # Local account names — mirrors commands/auth.sh's _auth_accounts (kept
    # inline: bin/rp dispatches _complete without sourcing commands/*.sh).
    [[ -d "$RP_CREDS_DIR" ]] || return 0
    for f in "$RP_CREDS_DIR"/*; do
      [[ -f "$f" ]] && basename "$f"
    done
    ;;
  pod | volume | serverless | template | registry | cluster)
    rp::complete_resource_ids "$1"
    ;;
  esac
  return 0
}

# "id<TAB>name" lines for a descriptor resource, through the TTL cache.
# Cache format: first line "<fetch-epoch>\t<resource>", then one line per
# record. Everything after a failed refresh leaves the old cache untouched.
rp::complete_resource_ids() {
  local res="$1" ts now
  local cache="$RP_CONFIG_HOME/completion/$res"
  if [[ ! -f "$cache" ]]; then
    rp::complete_refresh "$res" || return 0
    grep -v '^[0-9]' "$cache" 2>/dev/null
    return 0
  fi
  IFS=$'\t' read -r ts _ <"$cache"
  now="${EPOCHREALTIME%.*}"
  if ((now - ts <= _RP_COMPLETE_TTL)); then
    grep -v '^[0-9]' "$cache"
    return 0
  fi
  # Stale: print what we have; refresh in the background so the next TAB is
  # warm. The double subshell orphans the job — it must outlive rp.
  if [[ -n "${RP_COMPLETION_SYNC_REFRESH:-}" ]]; then
    rp::complete_refresh "$res" >/dev/null 2>&1 || true
  else
    (rp::complete_refresh "$res" >/dev/null 2>&1 &) >/dev/null 2>&1
  fi
  grep -v '^[0-9]' "$cache"
  return 0
}

# Fetch a resource list and (re)write its cache atomically. Dies quietly on
# any failure — a completion cache is best-effort by contract.
rp::complete_refresh() {
  local res="$1" body tmp
  _resource_meta "$res" || return 1
  body="$(rp::http GET "$RP_RES_PATH")" || return 1
  mkdir -p "$RP_CONFIG_HOME/completion"
  _mktemp tmp
  {
    printf '%s\t%s\n' "${EPOCHREALTIME%.*}" "$res"
    rp::unwrap "$RP_RES_KEY" "$body" |
      jq -r '(. // []) | .[] | select(.id != null) | [(.id | tostring), (.name // "")] | @tsv'
  } >"$tmp" 2>/dev/null || return 1
  mv "$tmp" "$RP_CONFIG_HOME/completion/$res"
}
