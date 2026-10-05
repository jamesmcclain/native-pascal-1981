#!/usr/bin/env bash
# Test-only C compiler for the driver. scripts/test-env.sh points
# PASCAL1981_CC here and PASCAL1981_TEST_CC at the real compiler.
# Compilers print harmless text that varies by version and host: clang's
# driver warnings about its installation (for example
# -Wgcc-install-dir-libstdcxx), warnings tagged [-W...], and the
# "N warnings generated." summary. Many suites require the driver's stderr
# to be empty so that the Pascal stages stay quiet, so drop exactly those
# clang warning lines. Errors and the exit status pass through.
set -uo pipefail
{ "${PASCAL1981_TEST_CC:?}" "$@" 2>&1 1>&3 3>&- |
    sed -E -e '/^[^ :]*clang[^ :]*: warning: /d' \
      -e '/^([^ ]+: )?warning: .*\[-W[^]]+\]$/d' \
      -e '/^[0-9]+ warnings? generated\.$/d' >&2
  status=${PIPESTATUS[0]}; } 3>&1
exit "$status"
