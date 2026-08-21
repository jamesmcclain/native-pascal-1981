#!/usr/bin/env bash
# Format C (GNU indent) and Python sources in place.
# find -exec is used instead of `$(find | grep ...)` so paths with
# whitespace can't word-split, and skips .git/venv/build byproducts.
set -euo pipefail
cd "$(dirname "$0")/.."

fail_broken() {
    local tool="$1" hint="$2"
    echo "beautify.sh: '$tool' is on PATH but does not run (broken install," >&2
    echo "or a shebang pointing at a Python environment that no longer has" >&2
    echo "it installed). $hint" >&2
    exit 1
}

indent_hint="Install GNU indent (e.g. apt install indent, brew install gnu-indent)."
isort_hint="Install with: pip install isort (into whichever Python environment's bin/ is first on PATH)."
yapf_hint="Install with: pip install yapf (into whichever Python environment's bin/ is first on PATH)."

# indent is a hard requirement: the compiler driver's runtime/*.c always
# exists, so a broken indent means this script can never succeed. isort/yapf
# are soft requirements below -- tests/*.py is optional in this repo, so
# their outright ABSENCE is not fatal -- but present-and-broken still is: a
# formatter can pass `command -v` (e.g. a `pip install --user` shim whose
# shebang points at a Python environment that no longer has the package)
# while not actually running, which would otherwise surface as a bare
# ModuleNotFoundError traceback deep inside a `find -exec` invocation,
# reading like a bug in this script rather than what it is: a broken local
# toolchain. Silently downgrading that to "skip Python formatting" (the
# same as genuine absence) would mask a real error, so it fails loudly
# instead, same as indent.
if ! command -v indent >/dev/null 2>&1; then
    echo "beautify.sh: 'indent' not found on PATH. $indent_hint" >&2
    exit 1
fi
# Not `indent --version`: GNU indent exits nonzero on it regardless of
# whether the binary works (a documented quirk, not a health signal), so
# probe the same way it's actually used instead -- format a trivial
# snippet through stdin/stdout, which does exit 0 on a working install.
printf 'int f(void){return 1;}\n' | indent >/dev/null 2>&1 || fail_broken indent "$indent_hint"

# Format C runtime sources. The compiler driver is Pascal.
VERSION_CONTROL=none find runtime -name '*.c' -exec indent -kr -nut -l180 {} +

# Format Python test files if present
if find tests -name '*.py' 2>/dev/null | grep -q .; then
    if command -v isort >/dev/null 2>&1; then
        isort --version >/dev/null 2>&1 || fail_broken isort "$isort_hint"
        find tests -name '*.py' -not -path '*/__pycache__/*' -exec isort {} +
    fi
    if command -v yapf >/dev/null 2>&1; then
        yapf --version >/dev/null 2>&1 || fail_broken yapf "$yapf_hint"
        find tests -name '*.py' -not -path '*/__pycache__/*' -exec yapf -i {} +
    fi
fi
