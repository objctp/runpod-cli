#!/usr/bin/env bash
# Generate a GitHub-CLI-style markdown manual from `rp doc` output.
#
# Every user-facing command/verb already carries a reference block in its
# source comments, rendered by `rp doc`. This script reuses that surface so the
# manual has a full page per command and per verb (gh manual layout):
#   docs/<command>.md              category page (overview + linked commands)
#   docs/<command>-<verb>.md      one independent page per verb
#   docs/<command>-<group>-<subverb>.md   for group verbs (e.g. registry delegations)
# plus an index.md. The markdown is the standalone source of truth — edit the
# pages directly; this script is only the seed that creates them.
#
# Usage: scripts/gen-manual.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/docs"
mkdir -p "$OUT"

rpdoc() { "$ROOT/bin/rp" doc "$@" 2>/dev/null; }

# Normalise spacing: ensure a single blank line around each code-fence block
# (before an opener, after a closer) without breaching the block's own content,
# then collapse any runs of blank lines to one. Fence state is tracked so a
# blank is added only outside a block, never between a fence and its content.
normalize() {
  awk '
    function fence(s){ return s ~ /^```/ }
    { line=$0
      isf = fence(line)
      need = 0
      if (line != "" && prev != "") {
        if (isf && prev_inf == 0) need = 1            # prose -> opener
        if (!isf && prev_isf == 1 && inf == 0) need = 1  # closer -> prose
      }
      if (isf) inf = !inf
      if (need) print ""
      print line
      prev = line; prev_isf = isf; prev_inf = inf
    }
  ' | awk 'BEGIN{pb=0} { if($0==""){ if(pb) next; pb=1 } else pb=0; print }'
}

# Transform `rp doc` text (stdin) into markdown. $1 = heading level for the
# title line (`rp …`). The usage line is emitted as a fenced block directly
# under the description (no SYNOPSIS heading, gh-CLI style); fenced blocks for
# Arguments/Options/Examples; prose for Notes; the Verbs: list becomes a
# COMMANDS bullet list.
transform() {
  awk -v hl="$1" '
    function hashes(n,  s){ s=""; for(i=0;i<n;i++) s=s"#"; return s }
    function closefence(){ if(fence){ print "```"; fence=0 } }
    function openfence(tag){
      closefence(); cur=tag
      print hashes(hl+1) " " tag
      print "```"; fence=1
    }
    BEGIN { base="" }
    NR==1 && $0 ~ /^rp / {
      base = substr($0, 4)                 # strip leading "rp "
      print hashes(hl) " " $0
      next
    }
    /^$/ { closefence(); if(cur=="NOTES") print ""; cur=""; next }
    /^Usage:/ {
      closefence(); cur="USAGE"
      print "```"; fence=1
      rest = substr($0, 8); gsub(/^[ \t]+/, "", rest)
      if (rest != "") print rest
      next
    }
    /^Arguments:/  { openfence("ARGUMENTS"); next }
    /^Options:/    { openfence("OPTIONS");   next }
    /^Examples:/   { openfence("EXAMPLES");  next }
    /^Notes:/      { closefence(); cur="NOTES"; print hashes(hl+1) " NOTES";     next }
    /^API:/ {
      closefence(); cur=""
      line = substr($0, 5); gsub(/^[ \t]+/, "", line)
      printf "\n**API:** `%s`\n\n", line
      next
    }
    /^Verbs:/ { closefence(); cur="VERBS"; print hashes(hl+1) " COMMANDS"; print ""; next }
    {
      if (cur == "VERBS") {
        if ($0 ~ /^  [a-z]/) {
          v = $1
          rest = $0; sub(/^  [a-z][a-z-]*[ \t]+/, "", rest)
          link = base " " v; gsub(/ /, "-", link)
          printf "- [`rp %s %s`](%s.md) — %s\n", base, v, link, rest
        }
        next
      }
      if (cur=="USAGE" || cur=="ARGS" || cur=="OPTS" || cur=="EX") { print $0; next }
      if (cur=="NOTES") { print $0; next }
      print $0
    }
    END { closefence() }
  '
}

# Collect verb names from a command-level `rp doc` dump.
verbs_of() { awk '/^Verbs:/{f=1;next} f&&/^  [a-z]/{print $1}' <<<"$1"; }

# True when $1 (a `rp doc <verb>` dump) is a group verb (owns a Verbs: list).
is_group() { grep -q '^Verbs:' <<<"$1"; }

# Render one command as a gh-CLI-style tree: docs/<name>.md is the category
# page (overview + linked command list); each verb is its own page
# docs/<name>-<verb>.md. A group verb (one owning sub-verbs, e.g. `registry
# delegations`) gets its own category page docs/<name>-<verb>.md plus a page
# per sub-verb docs/<name>-<verb>-<subverb>.md.
gen_command() {
  local name="$1" text verbs
  text="$(rpdoc "$name")"
  verbs="$(verbs_of "$text")"
  # Category page: overview + linked list of commands.
  { transform 1 <<<"$text"; } | normalize >"$OUT/$name.md"
  printf 'docs/%s.md\n' "$name"
  for v in $verbs; do
    local vt
    vt="$(rpdoc "$name" "$v")"
    if is_group "$vt"; then
      { transform 1 <<<"$vt"; } | normalize >"$OUT/$name-$v.md"
      printf 'docs/%s.md\n' "$name-$v"
      local subs
      subs="$(verbs_of "$vt")"
      for s in $subs; do
        { transform 1 <<<"$(rpdoc "$name" "$v" "$s")"; } | normalize >"$OUT/$name-$v-$s.md"
        printf 'docs/%s.md\n' "$name-$v-$s"
      done
    else
      { transform 1 <<<"$vt"; } | normalize >"$OUT/$name-$v.md"
      printf 'docs/%s.md\n' "$name-$v"
    fi
  done
}

# Render index.md: one line per command (name + intro summary).
gen_index() {
  {
    echo "# rp manual"
    echo
    echo "Reference for the RunPod CLI (\`rp\`). Each command has its own page:"
    echo
    rpdoc | while read -r line; do
      # lines look like: "rp pod          On-demand GPU ..."
      [[ "$line" =~ ^rp\ ([a-z-]+)[[:space:]]+(.*)$ ]] || continue
      printf -- '- [%s](%s.md) — %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    done
  } | normalize >"$OUT/index.md"
  echo "docs/index.md"
}

# Regenerate a subset of commands when names are passed (incremental mode, used
# by the pre-commit hook), or the whole tree when called with no arguments.
# A named command whose source `commands/<name>.sh` no longer exists is treated
# as deleted: its doc pages are removed so manual and CLI never diverge. The
# index is always refreshed (one `rp doc` call) since any command's summary may
# have changed.
main() {
  local -a names=("$@")
  if [ ${#names[@]} -eq 0 ]; then
    for f in "$ROOT"/commands/*.sh; do
      names+=("$(basename "$f" .sh)")
    done
  fi
  local c
  for c in "${names[@]}"; do
    if [ -f "$ROOT/commands/$c.sh" ]; then
      gen_command "$c"
    else
      rm -f "$OUT/$c.md" "$OUT/$c-"*.md
      echo "docs/$c*.md (removed)"
    fi
  done
  gen_index
}

main "$@"
