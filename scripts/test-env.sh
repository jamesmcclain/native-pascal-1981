#!/usr/bin/env bash
# Run a test suite without launching OS crash reporters for expected failures.
# Linux ignores RLIMIT_CORE for piped handlers; exec resets PR_SET_DUMPABLE,
# so use a test-only constructor inherited by dynamically linked children.
set -euo pipefail
if [ "$#" -eq 0 ]; then
  echo "usage: $0 <test-command> [args...]" >&2
  exit 2
fi
# Compile through scripts/test-cc.sh, which drops the host clang's own
# driver warnings so suites asserting an empty compiler stderr do not
# depend on how the host's toolchain is installed. A suite that sets
# PASCAL1981_CC itself (a fake clang) still overrides this.
if [ -z "${PASCAL1981_TEST_CC:-}" ]; then
  export PASCAL1981_TEST_CC="${PASCAL1981_CC:-${CC:-clang}}"
  export PASCAL1981_CC="$(cd "$(dirname "$0")" && pwd)/test-cc.sh"
fi
if [ "${PASCAL_TEST_CORES:-0}" = 1 ]; then
  exec "$@"
fi
ulimit -c 0
if [ "$(uname -s)" = Linux ]; then
  root="$(cd "$(dirname "$0")/.." && pwd)"
  # Tiny independent target; never invokes the compiler bootstrap. Make
  # caches it, and standalone focused suites can use this launcher too.
  MAKEFLAGS= make -s -C "$root" build/test-no-core.so
  shim="$root/build/test-no-core.so"
  case ":${LD_PRELOAD:-}:" in
    *":$shim:"*) ;;
    *) export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}" ;;
  esac
fi
exec "$@"
