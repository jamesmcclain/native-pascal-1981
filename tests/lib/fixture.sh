# Fixture directives, shared by the corpus runner (tests/corpus/fixtures.sh)
# and the suites that walk the same corpus (mathck_twins). Source it after
# tests/lib/harness.sh.
#
# A directive is a Pascal comment `{ KEY: value }` anywhere in a fixture,
# alone on its part of the line; a key may appear more than once.

# One sed each, not a pipeline: a reader that stops early (head) would make
# the writer fail with SIGPIPE, which pipefail turns into a failure.
directive_values() { # file KEY: each value of `{ KEY: value }`, one per line
  sed -nE "/\{ *$2: */{s/^.*\{ *$2: *//; s/ *\}[[:space:]]*\$//; p}" "$1"
}
directive_value() { # file KEY: the first value of `{ KEY: value }`
  sed -nE "/\{ *$2: */{s/^.*\{ *$2: *//; s/ *\}[[:space:]]*\$//; p; q}" "$1"
}

# The dialects a fixture is compiled in, one per line: the words of its
# DIALECT directive (`{ DIALECT: vintage extended }` asks for both), else
# the content of a sibling <name>.dialect file, else nothing (the driver's
# default). Fails on a word that is not a dialect.
fixture_dialects() { # file
  local words word
  words=$(directive_value "$1" DIALECT)
  if [ -z "$words" ] && [ -f "${1%.*}.dialect" ]; then
    words=$(< "${1%.*}.dialect")
  fi
  for word in $words; do
    case "$word" in
      vintage | extended) echo "$word" ;;
      *) echo "error: invalid dialect '$word' in $1" >&2; return 1 ;;
    esac
  done
}
