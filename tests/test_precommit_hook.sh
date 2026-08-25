#!/usr/bin/env bash
# Tests for the tracked pre-commit hook and beautify.sh.
set -uo pipefail
cd "$(dirname "$0")/.."

ROOT=$PWD
HOOK="$ROOT/scripts/hooks/pre-commit"
BEAUTIFY="$ROOT/scripts/beautify.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

pass=0
fail=0
skip=0

pass_test() {
    echo "PASS: $1"
    pass=$((pass + 1))
}

fail_test() {
    echo "FAIL: $1${2:+: $2}" >&2
    fail=$((fail + 1))
}

skip_test() {
    echo "SKIP: $1${2:+: $2}"
    skip=$((skip + 1))
}

assert_status() {
    local name=$1 expected=$2 actual=$3
    if [ "$actual" -eq "$expected" ]; then
        pass_test "$name"
    else
        fail_test "$name" "expected status $expected, got $actual"
    fi
}

assert_failure_contains() {
    local name=$1 status=$2 needle=$3 output=$4
    if [ "$status" -eq 0 ]; then
        fail_test "$name" "command succeeded"
    elif ! grep -qF -- "$needle" "$output"; then
        fail_test "$name" "output did not contain '$needle'"
        cat "$output" >&2
    else
        pass_test "$name"
    fi
}

write_ugly_files() {
    local repo=$1
    printf 'int   f( int x ){return x   ;}\n' > "$repo/runtime/a.c"
    printf 'x = {   "a":1 }\n' > "$repo/tests/z.py"
}

make_tool_path() {
    local dir=$1
    shift
    mkdir -p "$dir"
    local tool path
    for tool in "$@"; do
        path=$(command -v "$tool") || return 1
        ln -s "$path" "$dir/$tool"
    done
}

setup_beautify_repo() {
    local name=$1
    BEAUTIFY_REPO="$work_dir/$name/repo"
    mkdir -p "$BEAUTIFY_REPO/runtime" "$BEAUTIFY_REPO/tests" "$BEAUTIFY_REPO/scripts"
    cp "$BEAUTIFY" "$BEAUTIFY_REPO/scripts/beautify.sh"
    write_ugly_files "$BEAUTIFY_REPO"
}

run_beautify() {
    local repo=$1 path=$2
    local status=0
    PATH="$path" /bin/bash "$repo/scripts/beautify.sh" > "$repo/stdout" 2> "$repo/stderr" || status=$?
    return "$status"
}

test_hook_is_tracked_and_executable() {
    local name='hook is tracked and executable'
    if ! command -v git >/dev/null 2>&1; then
        skip_test "$name" 'git is not available'
        return
    fi

    local record
    record=$(git ls-files -s scripts/hooks/pre-commit)
    if [ -z "$record" ]; then
        fail_test "$name" 'scripts/hooks/pre-commit is not tracked'
    elif [ "${record%% *}" != 100755 ]; then
        fail_test "$name" "expected mode 100755, got ${record%% *}"
    else
        pass_test "$name"
    fi
}

test_broken_indent() {
    local name='broken indent fails with an actionable message'
    setup_beautify_repo broken-indent
    local tools="$work_dir/broken-indent/tools"
    make_tool_path "$tools" bash dirname find grep
    cat > "$tools/indent" <<'EOF'
#!/usr/bin/env bash
echo "indent: broken" >&2
exit 1
EOF
    chmod +x "$tools/indent"

    local status=0
    run_beautify "$BEAUTIFY_REPO" "$tools" || status=$?
    if [ "$status" -eq 0 ] || ! grep -qF 'indent' "$BEAUTIFY_REPO/stderr" ||
       ! grep -qF 'does not run' "$BEAUTIFY_REPO/stderr"; then
        fail_test "$name" 'the expected diagnostic was not produced'
    elif ! grep -qF 'int   f( int x ){return x   ;}' "$BEAUTIFY_REPO/runtime/a.c"; then
        fail_test "$name" 'the C file changed'
    else
        pass_test "$name"
    fi
}

test_missing_indent() {
    local name='missing indent fails with an actionable message'
    setup_beautify_repo missing-indent
    local tools="$work_dir/missing-indent/tools"
    make_tool_path "$tools" bash dirname find grep

    local status=0
    run_beautify "$BEAUTIFY_REPO" "$tools" || status=$?
    if [ "$status" -eq 0 ] || ! grep -qF 'indent' "$BEAUTIFY_REPO/stderr" ||
       ! grep -qF 'not found on PATH' "$BEAUTIFY_REPO/stderr"; then
        fail_test "$name" 'the expected diagnostic was not produced'
    elif ! grep -qF 'int   f( int x ){return x   ;}' "$BEAUTIFY_REPO/runtime/a.c"; then
        fail_test "$name" 'the C file changed'
    else
        pass_test "$name"
    fi
}

test_broken_isort() {
    local name='broken isort fails even though it is optional'
    if ! command -v indent >/dev/null 2>&1; then
        skip_test "$name" 'indent is not available'
        return
    fi

    setup_beautify_repo broken-isort
    local tools="$work_dir/broken-isort/tools"
    make_tool_path "$tools" bash dirname find grep indent
    cat > "$tools/isort" <<'EOF'
#!/usr/bin/env bash
echo "ModuleNotFoundError: No module named 'isort'" >&2
exit 1
EOF
    chmod +x "$tools/isort"

    local status=0
    run_beautify "$BEAUTIFY_REPO" "$tools" || status=$?
    if [ "$status" -eq 0 ] || ! grep -qF 'isort' "$BEAUTIFY_REPO/stderr" ||
       ! grep -qF 'does not run' "$BEAUTIFY_REPO/stderr"; then
        fail_test "$name" 'the expected diagnostic was not produced'
    elif ! grep -qF 'x = {   "a":1 }' "$BEAUTIFY_REPO/tests/z.py"; then
        fail_test "$name" 'the Python file changed'
    else
        pass_test "$name"
    fi
}

test_missing_python_formatters() {
    local name='missing isort and yapf is not fatal'
    if ! command -v indent >/dev/null 2>&1; then
        skip_test "$name" 'indent is not available'
        return
    fi

    setup_beautify_repo missing-python-formatters
    local tools="$work_dir/missing-python-formatters/tools"
    make_tool_path "$tools" bash dirname find grep indent

    local status=0
    run_beautify "$BEAUTIFY_REPO" "$tools" || status=$?
    if [ "$status" -ne 0 ]; then
        fail_test "$name" "beautify.sh returned $status"
        cat "$BEAUTIFY_REPO/stderr" >&2
    elif ! grep -qF 'int f(int x)' "$BEAUTIFY_REPO/runtime/a.c"; then
        fail_test "$name" 'the C file was not formatted'
    elif ! grep -qF 'x = {   "a":1 }' "$BEAUTIFY_REPO/tests/z.py"; then
        fail_test "$name" 'the Python file changed'
    else
        pass_test "$name"
    fi
}

test_hook_is_tracked_and_executable
test_broken_indent
test_missing_indent
test_broken_isort
test_missing_python_formatters

echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
