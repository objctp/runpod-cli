#!/usr/bin/env bash
# Documentation extraction — turns the comment-based docs already embedded in
# command files into a queryable surface for `rp doc`. Only user-facing commands
# are documented (never library internals like rp::http): each command's
# file-header intro, and per-verb blocks marked with a `# doc: <verb>` comment
# (or, as a fallback, the comment above the `_<resource>_<verb>` handler). The
# docs are "non-verbalized": they live in comments, never in --help.
[[ -n "${_RP_DOC:-}" ]] && return 0
_RP_DOC=1

# Per-file parse cache. Every doc query used to re-read the whole command file
# with a `while read` loop — one builtin iteration plus a regex test per line,
# per query — so `rp doc pod` scanned commands/pod.sh once per verb (~17 full
# passes, ~40 ms each). The file is now read once per process with mapfile and
# indexed in ONE pass (verb markers, function-comment runs, verb and sub-verb
# lists); every query is then an O(block) lookup instead of an O(file) scan.
declare -gA _RP_DOC_LOADED=()
declare -gA _RP_DOC_INTRO=()
# Index tables, keyed "<file-key>|<verb|func|group>" (verbs are keyed by the
# file key alone):
declare -gA _RP_DOC_MARKER=()   # verb        -> line index where its block starts
declare -gA _RP_DOC_FUNC=()     # func name   -> line index where its comment run starts
declare -gA _RP_DOC_SUBVERBS=() # group       -> newline-terminated sub-verb labels
declare -gA _RP_DOC_VERBS=()    # file key    -> newline-terminated verb labels
declare -gA _RP_DOC_IDX=()      # file key    -> index built
# Name of the cached line array for the most recently parsed file; callers
# bind a nameref to it (`local -n lines="$_RP_DOC_KEY"`).
_RP_DOC_KEY=""

# Slurp $1 into a cached global indexed array and point _RP_DOC_KEY at it. The
# array name folds the path to [A-Za-z0-9_] so one global array per file is
# reused across every query in the process.
_doc_slurp() {
  local file="$1"
  _RP_DOC_KEY="__rp_doc_lines_${file//[^A-Za-z0-9]/_}"
  [[ -n "${_RP_DOC_LOADED["$_RP_DOC_KEY"]:-}" ]] && return 0
  mapfile -t "$_RP_DOC_KEY" <"$file"
  _RP_DOC_LOADED["$_RP_DOC_KEY"]=1
}

# Build (once per file) the single-pass index used by every query below. The
# state machines replicate the original per-query scans exactly — each line is
# offered to the marker, function-comment, verb, and sub-verb machines in the
# same shapes those scans matched.
_doc_build_index() {
  local file="$1"
  _doc_slurp "$file"
  [[ -n "${_RP_DOC_IDX["$_RP_DOC_KEY"]:-}" ]] && return 0
  local -n lines="$_RP_DOC_KEY"
  local i line s vlabel
  local in_vcase=0
  local sgroup="" in_scase=0 sub_str=""
  local -a run=()
  for i in "${!lines[@]}"; do
    line="${lines[i]}"

    # Verb markers: `# doc: <verb>` — the block starts on the next line.
    # First occurrence wins (the original scan broke after the first capture).
    if [[ "$line" =~ ^[[:space:]]*#\ doc:\ ([-a-z0-9]+([[:space:]]+[-a-z0-9]+)*)[[:space:]]*$ ]]; then
      [[ -n "${_RP_DOC_MARKER["$_RP_DOC_KEY|${BASH_REMATCH[1]}"]:-}" ]] ||
        _RP_DOC_MARKER["$_RP_DOC_KEY|${BASH_REMATCH[1]}"]=$((i + 1))
    fi

    # Function-comment runs: a contiguous comment block immediately above a
    # `name() {` definition line. Comment lines extend the run; any other line
    # ends it (after possibly recording it for the definition that follows).
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      run+=("$i")
    else
      if [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:]*)[[:space:]]*\(\). ]]; then
        # The original scan kept looking past a definition with no comment
        # above it, so only a non-empty run records the name.
        if ((${#run[@]})) && [[ -z "${_RP_DOC_FUNC["$_RP_DOC_KEY|${BASH_REMATCH[2]}"]:-}" ]]; then
          _RP_DOC_FUNC["$_RP_DOC_KEY|${BASH_REMATCH[2]}"]="${run[0]}"
        fi
      fi
      run=()
    fi

    # Verb labels: arms of a `case "$verb" in` block, plus `"$verb" == "x"`
    # guard lines (group verbs), in source order — excluding help and *.
    if ((in_vcase)); then
      if [[ "$line" == *esac* ]]; then
        in_vcase=0
      elif [[ "$line" =~ ^[[:space:]]*([a-z][a-z0-9-]+)[[:space:]]*\) ]]; then
        vlabel="${BASH_REMATCH[1]}"
        [[ "$vlabel" == "help" || "$vlabel" == "*" ]] || _RP_DOC_VERBS["$_RP_DOC_KEY"]+="$vlabel"$'\n'
      fi
    elif [[ "$line" == *'case "$verb" in'* ]]; then
      in_vcase=1
    elif [[ "$line" =~ \"\$verb\"[[:space:]]*==[[:space:]]*\"([a-z][a-z0-9-]*)\" ]]; then
      vlabel="${BASH_REMATCH[1]}"
      [[ "$vlabel" == "help" || "$vlabel" == "*" ]] || _RP_DOC_VERBS["$_RP_DOC_KEY"]+="$vlabel"$'\n'
    fi

    # Sub-verb lists: once a `"$verb" == "<group>"` guard is seen, the labels
    # of the following `case "$sub" in` block belong to that group. While a
    # group is armed the original never re-armed on another guard line.
    if ((in_scase)); then
      if [[ "$line" == *esac* ]]; then
        _RP_DOC_SUBVERBS["$_RP_DOC_KEY|$sgroup"]="$sub_str"
        sgroup=""
        in_scase=0
        sub_str=""
      elif [[ "$line" =~ ^[[:space:]]*([a-z][a-z0-9-]+)[[:space:]]*\) ]]; then
        vlabel="${BASH_REMATCH[1]}"
        [[ "$vlabel" == "help" || "$vlabel" == "*" ]] || sub_str+="$vlabel"$'\n'
      fi
    elif [[ -n "$sgroup" ]]; then
      [[ "$line" == *'case "$sub" in'* ]] && in_scase=1
    elif [[ "$line" =~ \"\$verb\"[[:space:]]*==[[:space:]]*\"([a-z][a-z0-9-]*)\" ]]; then
      sgroup="${BASH_REMATCH[1]}"
      sub_str=""
    fi
  done
  _RP_DOC_IDX["$_RP_DOC_KEY"]=1
}

# Trim leading and trailing empty entries from nameref array $1.
_doc_trim() {
  local -n doc_trim_arr="$1"
  while ((${#doc_trim_arr[@]})) && [[ -z "${doc_trim_arr[0]}" ]]; do
    doc_trim_arr=("${doc_trim_arr[@]:1}")
  done
  while ((${#doc_trim_arr[@]})) && [[ -z "${doc_trim_arr[-1]}" ]]; do
    unset 'doc_trim_arr[${#doc_trim_arr[@]}-1]'
  done
}

# Compute the file-header intro of a command file once and cache it: sets
# _RP_DOC_KEY (via _doc_slurp) and stores the rendered text — "" when the file
# has no intro — in that file's _RP_DOC_INTRO entry, so `rp doc`'s catalogue
# can derive the summary without a second parse or an awk fork.
_rp_doc_intro_get() {
  local file="$1"
  _doc_slurp "$file"
  [[ -n "${_RP_DOC_INTRO["$_RP_DOC_KEY"]+x}" ]] && return 0
  local -n lines="$_RP_DOC_KEY"
  local -a block=()
  local line skip_shebang=1 stripped
  for line in "${lines[@]}"; do
    if ((skip_shebang)); then
      [[ "$line" == \#!* ]] && continue
      skip_shebang=0
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      stripped="${line#"${line%%[![:space:]]*}"}"
      stripped="${stripped#\#}"
      stripped="${stripped# }"
      block+=("$stripped")
    else
      break
    fi
  done
  _doc_trim block
  local buf=""
  ((${#block[@]})) && printf -v buf '%s\n' "${block[@]}"
  _RP_DOC_INTRO["$_RP_DOC_KEY"]="$buf"
}

# The file-header intro of a command: the run of comment lines at the top of
# commands/<name>.sh (after the shebang), each with its leading "# " stripped.
# Prints the trimmed body; nothing if the file has no intro.
rp::doc_intro() {
  _rp_doc_intro_get "$1"
  # The cached text carries its own trailing newline (it IS the old stdout),
  # so print it verbatim — a '%s\n' would double the final blank line.
  [[ -n "${_RP_DOC_INTRO["$_RP_DOC_KEY"]}" ]] && printf '%s' "${_RP_DOC_INTRO["$_RP_DOC_KEY"]}"
  return 0
}

# First non-empty line of a command's intro — used by the catalogue. Pure bash
# over the cached intro: the old `| awk 'NF {print; exit}'` forked once per
# command on every `rp doc` invocation.
rp::doc_intro_summary() {
  local s
  _rp_doc_intro_get "$1"
  s="${_RP_DOC_INTRO["$_RP_DOC_KEY"]}"
  [[ -n "$s" ]] || return 0
  while [[ "$s" == $'\n'* ]]; do s="${s#$'\n'}"; done
  [[ -n "$s" ]] || return 0
  printf '%s\n' "${s%%$'\n'*}"
}

# The `# doc: <verb>` block for a verb in a command file. Prints the body
# (leading "# " stripped); nothing if the marker is absent. A marker name may
# carry a space (`# doc: delegations create`) so a sub-resource's verbs are
# addressed as the user types them, not under an invented hyphenated name.
rp::doc_verb_marker() {
  local file="$1" verb="$2"
  _doc_build_index "$file"
  local -a block=()
  local start="${_RP_DOC_MARKER["$_RP_DOC_KEY|$verb"]:-}"
  if [[ -n "$start" ]]; then
    local -n lines="$_RP_DOC_KEY"
    local i="$start" s n=${#lines[@]}
    while ((i < n)); do
      s="${lines[i]}"
      # Capture ends at a blank line, a non-comment, or the next doc: marker.
      [[ -z "$s" ]] && break
      [[ "$s" =~ ^[[:space:]]*# ]] || break
      s="${s#"${s%%[![:space:]]*}"}"
      s="${s#\#}"
      s="${s# }"
      [[ "$s" == doc:\ * ]] && break
      block+=("$s")
      ((i += 1))
    done
  fi
  _doc_trim block
  ((${#block[@]})) || return 0
  printf '%s\n' "${block[@]}"
}

# Fallback: the comment block immediately above a named function (e.g. the
# `_<resource>_<verb>` handler). Prints the body; nothing if undocumented.
rp::doc_func_doc() {
  local file="$1" target="$2"
  _doc_build_index "$file"
  local -a block=()
  local start="${_RP_DOC_FUNC["$_RP_DOC_KEY|$target"]:-}"
  if [[ -n "$start" ]]; then
    local -n lines="$_RP_DOC_KEY"
    local i="$start" s n=${#lines[@]} stripped
    # The run is contiguous comment lines by construction.
    while ((i < n)); do
      s="${lines[i]}"
      [[ "$s" =~ ^[[:space:]]*# ]] || break
      stripped="${s#"${s%%[![:space:]]*}"}"
      stripped="${stripped#\#}"
      stripped="${stripped# }"
      block+=("$stripped")
      ((i += 1))
    done
  fi
  ((${#block[@]})) || return 0
  _doc_trim block
  ((${#block[@]})) || return 0
  printf '%s\n' "${block[@]}"
}

# Verb names declared in a command's `case "$verb" in` block (excludes help/*),
# plus any *group* verb — one dispatched by an `if [[ "$verb" == "x" ]]` guard
# to its own sub-case rather than by a case arm (`rp registry delegations`).
# Groups are emitted where the guard appears, so the order this prints is the
# order the doc section must follow. Precomputed by _doc_build_index.
rp::doc_verbs() {
  local file="$1"
  _doc_build_index "$file"
  [[ -n "${_RP_DOC_VERBS["$_RP_DOC_KEY"]:-}" ]] && printf '%s' "${_RP_DOC_VERBS["$_RP_DOC_KEY"]}"
  return 0
}

# Sub-verb names of a group verb: the labels of the `case "$sub" in` block that
# follows the group's `if [[ "$verb" == "<group>" ]]` guard. Prints nothing when
# $2 is not a group. Precomputed by _doc_build_index.
rp::doc_subverbs() {
  local file="$1" group="$2"
  _doc_build_index "$file"
  [[ -n "${_RP_DOC_SUBVERBS["$_RP_DOC_KEY|$group"]:-}" ]] &&
    printf '%s' "${_RP_DOC_SUBVERBS["$_RP_DOC_KEY|$group"]}"
  return 0
}
