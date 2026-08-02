#!/usr/bin/env bash
#
# `rp doc` — surface the documentation embedded in command files (the
# descriptions and per-verb option notes that --help never prints). Only
# user-facing commands are documented, never library internals. `rp doc` lists
# every command; `rp doc <command>` shows a command's intro and verbs;
# `rp doc <command> <verb>` shows that verb's options/flags.
#

_doc_help() {
  cat <<'EOF'
Usage: rp doc [command] [verb]

Show non-verbalized documentation (source comments) for user-facing commands.

  rp doc                 list every command + a one-line summary
  rp doc serverless      intro and verbs of the serverless command
  rp doc serverless create   options/flags for the create verb

Verbs are documented with a `# doc: <verb>` marker block in the command file
(the comment above the `_<resource>_<verb>` handler also counts). Edit those
comments to grow what `rp doc` shows — no separate doc file to maintain.
EOF
}

# Resolve a command name to its file: exact match first, else the first command
# whose name starts with the arg (prefix). Prints the path, or nothing.
_doc_resolve() {
  local arg="$1" f
  [[ -f "$RP_ROOT/commands/$arg.sh" ]] && {
    printf '%s' "$RP_ROOT/commands/$arg.sh"
    return 0
  }
  for f in "$RP_ROOT"/commands/*.sh; do
    [[ "$(basename "$f" .sh)" == "$arg"* ]] && {
      printf '%s' "$f"
      return 0
    }
  done
  return 0
}

# Catalogue: one line per command (name + intro summary).
_doc_catalogue() {
  local f name summary
  for f in "$RP_ROOT"/commands/*.sh; do
    name="$(basename "$f" .sh)"
    summary="$(rp::doc_intro_summary "$f")"
    printf '%-16s %s\n' "rp $name" "$summary"
  done
}

# Command-level: intro + the verbs declared in its case block.
_doc_command() {
  local file="$1" name="$2" v
  printf '### rp %s\n' "$name"
  rp::doc_intro "$file"
  printf '\nVerbs:\n'
  rp::doc_verbs "$file" | while IFS= read -r v; do
    printf '  %s\n' "$v"
  done
}

# Verb-level: the `# doc: <verb>` block, or the handler's comment as a fallback.
_doc_verb() {
  local file="$1" name="$2" verb="$3" body found=0
  while IFS= read -r v; do
    [[ "$v" == "$verb" ]] && found=1
  done < <(rp::doc_verbs "$file")
  if ((!found)); then
    printf '%s\n' "no verb '$verb' for command '$name'"
    return 0
  fi
  body="$(rp::doc_verb_marker "$file" "$verb")"
  [[ -z "$body" ]] && body="$(rp::doc_func_doc "$file" "_${name}_${verb}")"
  printf '### rp %s %s\n' "$name" "$verb"
  if [[ -n "$body" ]]; then
    printf '%s\n' "$body"
  else
    printf '%s\n' "no documented options for '$name $verb' yet"
  fi
}

rp::cmd_doc() {
  local a="${1:-}" b="${2:-}"
  [[ "$a" == "-h" || "$a" == "--help" || "$a" == "help" ]] && {
    _doc_help
    return 0
  }
  if [[ -z "$a" ]]; then
    _doc_catalogue
    return 0
  fi
  local cmdfile
  cmdfile="$(_doc_resolve "$a")"
  if [[ -z "$cmdfile" ]]; then
    printf '%s\n' "no documentation matches '$a'"
    return 0
  fi
  local name
  name="$(basename "$cmdfile" .sh)"
  if [[ -z "$b" ]]; then
    _doc_command "$cmdfile" "$name"
  else
    _doc_verb "$cmdfile" "$name" "$b"
  fi
}
