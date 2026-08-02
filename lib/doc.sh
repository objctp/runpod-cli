#!/usr/bin/env bash
# Documentation extraction — turns the comment-based docs already embedded in
# command files into a queryable surface for `rp doc`. Only user-facing commands
# are documented (never library internals like rp::http): each command's
# file-header intro, and per-verb blocks marked with a `# doc: <verb>` comment
# (or, as a fallback, the comment above the `_<resource>_<verb>` handler). The
# docs are "non-verbalized": they live in comments, never in --help.
[[ -n "${_RP_DOC:-}" ]] && return 0
_RP_DOC=1

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

# The file-header intro of a command: the run of comment lines at the top of
# commands/<name>.sh (after the shebang), each with its leading "# " stripped.
# Prints the trimmed body; nothing if the file has no intro.
rp::doc_intro() {
  local file="$1"
  local -a block=()
  local line skip_shebang=1
  while IFS= read -r line; do
    if ((skip_shebang)); then
      [[ "$line" == \#!* ]] && continue
      skip_shebang=0
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      local stripped="${line#"${line%%[![:space:]]*}"}"
      stripped="${stripped#\#}"
      stripped="${stripped# }"
      block+=("$stripped")
    else
      break
    fi
  done <"$file"
  _doc_trim block
  ((${#block[@]})) || return 0
  printf '%s\n' "${block[@]}"
}

# First non-empty line of a command's intro — used by the catalogue.
rp::doc_intro_summary() {
  rp::doc_intro "$1" | awk 'NF {print; exit}'
}

# The `# doc: <verb>` block for a verb in a command file. Prints the body
# (leading "# " stripped); nothing if the marker is absent.
rp::doc_verb_marker() {
  local file="$1" verb="$2"
  local -a block=()
  local line capturing=0
  while IFS= read -r line; do
    if ((capturing)); then
      if [[ -z "$line" ]]; then break; fi
      if [[ "$line" =~ ^[[:space:]]*# ]]; then
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s#\#}"
        s="${s# }"
        [[ "$s" == doc:\ * ]] && break
        block+=("$s")
      else
        break
      fi
    elif [[ "$line" =~ ^[[:space:]]*#\ doc:\ ([-a-z0-9]+) ]]; then
      [[ "${BASH_REMATCH[1]}" == "$verb" ]] && capturing=1
    fi
  done <"$file"
  ((${#block[@]})) || return 0
  printf '%s\n' "${block[@]}"
}

# Fallback: the comment block immediately above a named function (e.g. the
# `_<resource>_<verb>` handler). Prints the body; nothing if undocumented.
rp::doc_func_doc() {
  local file="$1" target="$2"
  local -a block=()
  local line name found=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      local stripped="${line#"${line%%[![:space:]]*}"}"
      stripped="${stripped#\#}"
      stripped="${stripped# }"
      block+=("$stripped")
    elif [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:]*)[[:space:]]*\(\). ]]; then
      name="${BASH_REMATCH[2]}"
      if [[ "$name" == "$target" && ${#block[@]} -gt 0 ]]; then
        found=1
        break
      fi
      block=()
    else
      block=()
    fi
  done <"$file"
  ((found)) || return 0
  _doc_trim block
  ((${#block[@]})) || return 0
  printf '%s\n' "${block[@]}"
}

# Verb names declared in a command's `case "$verb" in` block (excludes help/*).
rp::doc_verbs() {
  local file="$1" line in_case=0 label
  while IFS= read -r line; do
    if ((in_case)); then
      [[ "$line" == *esac* ]] && {
        in_case=0
        continue
      }
      if [[ "$line" =~ ^[[:space:]]*([a-z][a-z0-9-]+)[[:space:]]*\) ]]; then
        label="${BASH_REMATCH[1]}"
        [[ "$label" == "help" || "$label" == "*" ]] && continue
        printf '%s\n' "$label"
      fi
    elif [[ "$line" == *'case "$verb" in'* ]]; then
      in_case=1
    fi
  done <"$file"
}
