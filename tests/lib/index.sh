#!/usr/bin/env bash
# Print the suite index of tests/README.md: one table row per suite, tier by
# tier, with the first sentence of the suite's header (the comment block
# after its harness line, or a Python suite's docstring).
#
#   tests/lib/index.sh            print the index
#   tests/lib/index.sh --update   rewrite it in tests/README.md, between
#                                 the suite-index markers
# tests/check/suite_index.sh fails when the README's copy is stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

summary() { # suite: the first sentence of its header
  local text
  case "$1" in
    *.py)
      text=$(python3 -c 'import ast, sys; print(ast.get_docstring(ast.parse(open(sys.argv[1]).read())) or "")' "$1")
      ;;
    *)
      text=$(awk 'NR == 1 || /^source / || /^# schedule:/ { next }
                  /^#/ { sub(/^# ?/, ""); print; found = 1; next }
                  found || NR > 4 { exit }' "$1")
      ;;
  esac
  printf '%s\n' "$text" | tr '\n' ' ' | sed -E 's/  +/ /g; s/^ //; s/\.( |$).*/./'
}

index() {
  local tier suite
  echo '| Tier | Suite | What it checks |'
  echo '| --- | --- | --- |'
  for tier in check unit corpus contract service optional; do
    find "tests/$tier" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) | sort |
      while read -r suite; do
        printf '| %s | [`%s`](%s) | %s |\n' "$tier" "$(basename "${suite%.*}")" \
          "${suite#tests/}" "$(summary "$suite" | sed 's/|/\\|/g')"
      done
  done
}

if [ "${1:-}" = --update ]; then
  readme=tests/README.md
  begin='<!-- suite-index:begin (tests/lib/index.sh --update) -->'
  end='<!-- suite-index:end -->'
  grep -qxF "$begin" "$readme" && grep -qxF "$end" "$readme" ||
    { echo "index: no suite-index markers in $readme" >&2; exit 1; }
  index > "$readme.index"
  awk -v begin="$begin" -v end="$end" -v file="$readme.index" '
    $0 == begin { print; while ((getline line < file) > 0) print line; skip = 1; next }
    $0 == end { skip = 0 }
    !skip' "$readme" > "$readme.new"
  rm "$readme.index"
  mv "$readme.new" "$readme"
else
  index
fi
