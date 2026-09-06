#!/usr/bin/env bash
#
# Read the manual embedded in rp's own source comments.
#
# `rp doc` is the reference surface: every user-facing command and verb carries
# a documentation block in its source file, and this command renders it. Where
# `--help` is a terse reminder of the flags, `rp doc` is the page you read to
# learn a command — arguments, defaults, constraints, caveats, examples, and the
# API call each verb makes. Library internals are never documented here.
#
# Usage: rp doc [command] [verb] [sub-verb]
#

_doc_help() {
  cat <<'EOF'
Usage: rp doc [command] [verb] [sub-verb]

Show the reference documentation for user-facing commands, read from the source
comments. `--help` lists the flags; `rp doc` explains them.

  rp doc                            every command with a one-line summary
  rp doc serverless                 a command's overview and its verbs
  rp doc serverless create          one verb: arguments, options, notes, examples
  rp doc registry delegations       a group verb's sub-verbs
  rp doc registry delegations create   one sub-verb

The command name may be abbreviated to any unique prefix (`rp doc serv`).

Verbs are documented by a `# doc: <verb>` block in the command file, collected
in one section above `rp::cmd_<command>`; the comment above a matching
`_<command>_<verb>` function is read as a fallback. Edit those comments to grow
what `rp doc` shows — there is no separate doc file to maintain.
EOF
}

# Resolve a command name to its file: exact match first, else a unique prefix
# match. Prints the path, or nothing; an ambiguous prefix is a usage error that
# names the candidates (never a silent pick of the alphabetically-first match).
_doc_resolve() {
  local arg="$1" f name
  if [[ -f "$RP_ROOT/commands/$arg.sh" ]]; then
    printf '%s' "$RP_ROOT/commands/$arg.sh"
    return 0
  fi
  local -a matches=()
  for f in "$RP_ROOT"/commands/*.sh; do
    name="${f##*/}"
    [[ "${name%.sh}" == "$arg"* ]] && matches+=("$f")
  done
  if ((${#matches[@]} == 1)); then
    printf '%s' "${matches[0]}"
    return 0
  fi
  if ((${#matches[@]} > 1)); then
    local names="" m
    for m in "${matches[@]}"; do names+=" $(basename "$m" .sh)"; done
    rp::usage "ambiguous command prefix '$arg' matches:$names"
  fi
  return 0
}

# A verb's documentation body: its `# doc:` block, else the comment above the
# matching handler function. $3 is the verb as the user types it, so a sub-verb
# arrives space-separated ("delegations create") and maps to the underscored
# handler name (_registry_delegations_create).
_doc_body() {
  local file="$1" name="$2" verb="$3" body
  body="$(rp::doc_verb_marker "$file" "$verb")"
  [[ -n "$body" ]] || body="$(rp::doc_func_doc "$file" "_${name}_${verb// /_}")"
  printf '%s' "$body"
}

# First line of a verb's block — the mandatory one-line summary, used by the
# verb index the way the intro's first line is used by the catalogue. Pure bash
# (the old `| awk 'NF {print; exit}'` forked once per verb page).
_doc_summary() {
  local s
  s="$(_doc_body "$1" "$2" "$3")"
  [[ -n "$s" ]] || return 0
  while [[ "$s" == $'\n'* ]]; do s="${s#$'\n'}"; done
  printf '%s\n' "${s%%$'\n'*}"
}

# Print "  <verb>  <summary>" rows, descriptions aligned to the longest verb.
# Reads verb names from stdin; $1 file, $2 command name, $3 optional prefix that
# makes each name a sub-verb ("delegations").
_doc_index() {
  local file="$1" name="$2" prefix="${3:-}" v width=0
  local -a verbs=()
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    verbs+=("$v")
    ((${#v} > width)) && width=${#v}
  done
  ((${#verbs[@]})) || return 0
  for v in "${verbs[@]}"; do
    printf '  %-*s  %s\n' "$width" "$v" "$(_doc_summary "$file" "$name" "${prefix:+$prefix }$v")"
  done
}

# Catalogue: one line per command (name + intro summary).
_doc_catalogue() {
  local f name summary
  for f in "$RP_ROOT"/commands/*.sh; do
    name="${f##*/}"
    summary="$(rp::doc_intro_summary "$f")"
    printf '%-16s %s\n' "rp ${name%.sh}" "$summary"
  done
}

# Command-level: intro, then the verb index. Commands with no verbs (rp api,
# rp upgrade) carry their flags in the intro, so the header is suppressed
# rather than printed above nothing.
_doc_command() {
  local file="$1" name="$2" index
  printf 'rp %s\n\n' "$name"
  rp::doc_intro "$file"
  index="$(rp::doc_verbs "$file" | _doc_index "$file" "$name")"
  [[ -n "$index" ]] || return 0
  printf '\nVerbs:\n%s\n' "$index"
}

# Group verb (rp registry delegations): its own block, then its sub-verb index.
_doc_group() {
  local file="$1" name="$2" group="$3" body index
  printf 'rp %s %s\n\n' "$name" "$group"
  body="$(_doc_body "$file" "$name" "$group")"
  [[ -z "$body" ]] || printf '%s\n' "$body"
  index="$(rp::doc_subverbs "$file" "$group" | _doc_index "$file" "$name" "$group")"
  [[ -n "$index" ]] || return 0
  printf '\nVerbs:\n%s\n' "$index"
}

# Verb-level: the `# doc: <verb>` block, or the handler's comment as a fallback.
_doc_verb() {
  local file="$1" name="$2" verb="$3" body
  printf 'rp %s %s\n\n' "$name" "$verb"
  body="$(_doc_body "$file" "$name" "$verb")"
  if [[ -n "$body" ]]; then
    printf '%s\n' "$body"
  else
    printf '%s\n' "no documented options for 'rp $name $verb' yet"
  fi
}

# True when $3 names a verb of command $2 (in $1).
_doc_is_verb() {
  local v
  while IFS= read -r v; do
    [[ "$v" == "$3" ]] && return 0
  done < <(rp::doc_verbs "$1")
  return 1
}

# True when $4 names a sub-verb of group $3.
_doc_is_subverb() {
  local v
  while IFS= read -r v; do
    [[ "$v" == "$4" ]] && return 0
  done < <(rp::doc_subverbs "$1" "$3")
  return 1
}

###
### :::: batch dump (scripts/gen-manual.sh) :::: ###############################
###

# Emit every page gen-manual.sh needs for one command — the command page plus
# one page per verb and sub-verb — in a single rp process. Pages are framed by
# ASCII record-separator (0x1e) lines carrying the page key ("pod",
# "pod run", "registry delegations create"), so the generator splits them
# locally instead of paying one full rp startup per page (~180 spawns for the
# whole manual collapsed to one per command).
_doc_dump() {
  local cmdfile name v s
  cmdfile="$(_doc_resolve "${1:-}")" || return $?
  if [[ -z "$cmdfile" ]]; then
    rp::usage "no documentation matches '${1:-}'"
  fi
  name="${cmdfile##*/}"
  name="${name%.sh}"
  # Warm the index here too — same subshell-rebuild economics as rp::cmd_doc.
  _doc_build_index "$cmdfile"
  printf '\x1e%s\n' "$name"
  _doc_command "$cmdfile" "$name"
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    printf '\x1e%s %s\n' "$name" "$v"
    if [[ -n "$(rp::doc_subverbs "$cmdfile" "$v")" ]]; then
      _doc_group "$cmdfile" "$name" "$v"
      while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        printf '\x1e%s %s %s\n' "$name" "$v" "$s"
        _doc_verb "$cmdfile" "$name" "$v $s"
      done < <(rp::doc_subverbs "$cmdfile" "$v")
    else
      _doc_verb "$cmdfile" "$name" "$v"
    fi
  done < <(rp::doc_verbs "$cmdfile")
}

###
### :::: documentation (rp doc doc) :::: ########################################
###

rp::cmd_doc() {
  local a="${1:-}" b="${2:-}" c="${3:-}"
  [[ "$a" == "-h" || "$a" == "--help" || "$a" == "help" ]] && {
    _doc_help
    return 0
  }
  # Tooling mode: one process, every page for a command (see _doc_dump).
  if [[ "$a" == "--dump" ]]; then
    _doc_dump "${b:-}"
    return 0
  fi
  if [[ -z "$a" ]]; then
    _doc_catalogue
    return 0
  fi
  local cmdfile
  cmdfile="$(_doc_resolve "$a")" || return $?
  if [[ -z "$cmdfile" ]]; then
    rp::usage "no documentation matches '$a'"
  fi
  local name
  name="${cmdfile##*/}"
  name="${name%.sh}"
  # Warm the one-pass file index in THIS shell before any query: every doc
  # query below runs in a $(), a pipe, or a process substitution, and a
  # subshell whose parent never built the index rebuilds it on entry
  # (~150 ms for a large command file — paid once per subshell otherwise).
  _doc_build_index "$cmdfile"
  if [[ -z "$b" ]]; then
    _doc_command "$cmdfile" "$name"
    return 0
  fi
  if ! _doc_is_verb "$cmdfile" "$name" "$b"; then
    rp::usage "no verb '$b' for command '$name'"
  fi
  # A group verb owns sub-verbs; without one, show its index rather than a
  # block that would only repeat what the index already says.
  if [[ -n "$(rp::doc_subverbs "$cmdfile" "$b")" ]]; then
    if [[ -z "$c" ]]; then
      _doc_group "$cmdfile" "$name" "$b"
    elif _doc_is_subverb "$cmdfile" "$name" "$b" "$c"; then
      _doc_verb "$cmdfile" "$name" "$b $c"
    else
      rp::usage "no sub-verb '$c' for '$name $b'"
    fi
    return 0
  fi
  _doc_verb "$cmdfile" "$name" "$b"
}
