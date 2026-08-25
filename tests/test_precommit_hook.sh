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

have_end_to_end_tools() {
    local tool
    for tool in git indent isort yapf; do
        command -v "$tool" >/dev/null 2>&1 || return 1
    done
}

setup_git_repo() {
    local name=$1
    TEST_REPO="$work_dir/$name/repo"
    TEST_HOME="$work_dir/$name/home"
    TEST_LOG_DIR="$work_dir/$name/log"
    mkdir -p "$TEST_REPO/runtime" "$TEST_REPO/tests" \
        "$TEST_REPO/scripts/hooks" "$TEST_HOME" "$TEST_LOG_DIR"
    cp "$BEAUTIFY" "$TEST_REPO/scripts/beautify.sh"
    cp "$HOOK" "$TEST_REPO/scripts/hooks/pre-commit"

    git_run init -q || return 1
    git_run config user.email test@example.invalid || return 1
    git_run config user.name Test || return 1
    git_run config commit.gpgsign false || return 1
    git_run config core.hooksPath scripts/hooks || return 1
    git_run add -A || return 1
    git_run commit -m initial || return 1
}

git_run() {
    GIT_STATUS=0
    GIT_CONFIG_NOSYSTEM=1 HOME="$TEST_HOME" GIT_TERMINAL_PROMPT=0 \
        env -u GIT_DIR git -C "$TEST_REPO" "$@" \
        > "$TEST_LOG_DIR/git.stdout" 2> "$TEST_LOG_DIR/git.stderr" || GIT_STATUS=$?
    return "$GIT_STATUS"
}

write_ugly_c() {
    printf 'int   f( int x ){return x   ;}\n' > "$1"
}

write_tidy_c() {
    printf 'int f(int x)\n{\n    return x;\n}\n' > "$1"
}

skip_end_to_end_test() {
    local name=$1
    if ! have_end_to_end_tools; then
        skip_test "$name" 'git, indent, isort, and yapf are required'
        return 0
    fi
    return 1
}

test_reformats_and_restages_staged_file() {
    local name='staged file is reformatted and restaged'
    skip_end_to_end_test "$name" && return
    setup_git_repo restage || { fail_test "$name" 'repository setup failed'; return; }
    write_ugly_c "$TEST_REPO/runtime/a.c"
    git_run add runtime/a.c
    if ! git_run commit -m 'add a.c'; then
        fail_test "$name" "commit returned $GIT_STATUS"
        cat "$TEST_LOG_DIR/git.stderr" >&2
        return
    fi
    git_run show HEAD:runtime/a.c
    write_tidy_c "$TEST_REPO/expected.c"
    if cmp -s "$TEST_REPO/expected.c" "$TEST_LOG_DIR/git.stdout"; then
        pass_test "$name"
    else
        fail_test "$name" 'committed content was not formatted'
    fi
}

test_worktree_clean_after_commit() {
    local name='worktree is clean after commit'
    skip_end_to_end_test "$name" && return
    setup_git_repo clean-worktree || { fail_test "$name" 'repository setup failed'; return; }
    write_ugly_c "$TEST_REPO/runtime/a.c"
    git_run add runtime/a.c
    git_run commit -m 'add a.c'
    git_run status --porcelain
    if [ "$GIT_STATUS" -eq 0 ] && [ ! -s "$TEST_LOG_DIR/git.stdout" ]; then
        pass_test "$name"
    else
        fail_test "$name" 'the worktree is not clean'
        cat "$TEST_LOG_DIR/git.stdout" >&2
    fi
}

test_unstaged_file_is_not_committed() {
    local name='unstaged file is not added to commit'
    skip_end_to_end_test "$name" && return
    setup_git_repo loose-file || { fail_test "$name" 'repository setup failed'; return; }
    write_ugly_c "$TEST_REPO/runtime/staged.c"
    write_ugly_c "$TEST_REPO/runtime/loose.c"
    git_run add runtime/staged.c
    git_run commit -m 'add staged.c'
    git_run show --name-only --format= HEAD
    local files
    files=$(tr -d '\r' < "$TEST_LOG_DIR/git.stdout")
    git_run status --porcelain
    if [ "$files" != 'runtime/staged.c' ]; then
        fail_test "$name" "unexpected committed paths: $files"
    elif ! grep -qF '?? runtime/loose.c' "$TEST_LOG_DIR/git.stdout"; then
        fail_test "$name" 'the loose file is not untracked'
    else
        pass_test "$name"
    fi
}

test_python_file_is_restaged() {
    local name='formatted Python file is restaged'
    skip_end_to_end_test "$name" && return
    setup_git_repo python-restage || { fail_test "$name" 'repository setup failed'; return; }
    printf 'x = {   "a":1 }\n' > "$TEST_REPO/tests/z_fmt.py"
    git_run add tests/z_fmt.py
    git_run commit -m 'add py'
    git_run show HEAD:tests/z_fmt.py
    if [ "$(cat "$TEST_LOG_DIR/git.stdout")" != 'x = {"a": 1}' ]; then
        fail_test "$name" 'committed Python content was not formatted'
    else
        git_run status --porcelain
        if [ -s "$TEST_LOG_DIR/git.stdout" ]; then
            fail_test "$name" 'the worktree is not clean'
        else
            pass_test "$name"
        fi
    fi
}

test_formatted_file_is_quiet() {
    local name='formatted file produces no hook output'
    skip_end_to_end_test "$name" && return
    setup_git_repo quiet || { fail_test "$name" 'repository setup failed'; return; }
    write_tidy_c "$TEST_REPO/runtime/tidy.c"
    git_run add runtime/tidy.c
    git_run commit -m 'add tidy.c'
    local status=$GIT_STATUS
    cat "$TEST_LOG_DIR/git.stdout" "$TEST_LOG_DIR/git.stderr" > "$TEST_LOG_DIR/commit.output"
    if [ "$status" -ne 0 ]; then
        fail_test "$name" "commit returned $status"
    elif grep -qF 're-staged' "$TEST_LOG_DIR/commit.output"; then
        fail_test "$name" 'the hook reported a restaged file'
    else
        git_run status --porcelain
        if [ -s "$TEST_LOG_DIR/git.stdout" ]; then
            fail_test "$name" 'the worktree is not clean'
        else
            pass_test "$name"
        fi
    fi
}

test_empty_stage() {
    local name='empty stage does not fail under set -u'
    skip_end_to_end_test "$name" && return
    setup_git_repo empty-stage || { fail_test "$name" 'repository setup failed'; return; }
    git_run commit --allow-empty -m empty
    assert_status "$name" 0 "$GIT_STATUS"
}

test_partially_staged_file_warns() {
    local name='partially staged file warns and commits'
    skip_end_to_end_test "$name" && return
    setup_git_repo partial || { fail_test "$name" 'repository setup failed'; return; }
    write_tidy_c "$TEST_REPO/runtime/p.c"
    git_run add runtime/p.c
    git_run commit -m 'seed p.c'

    { write_tidy_c /dev/stdout; echo; write_ugly_c /dev/stdout; } > "$TEST_REPO/runtime/p.c"
    git_run add runtime/p.c
    {
        write_tidy_c /dev/stdout
        echo
        write_ugly_c /dev/stdout
        echo
        printf 'int c(void)\n{\n    return 3;\n}\n'
    } > "$TEST_REPO/runtime/p.c"

    git_run commit -m partial
    local status=$GIT_STATUS
    if [ "$status" -ne 0 ]; then
        fail_test "$name" "commit returned $status"
    elif ! grep -qF 'partially staged' "$TEST_LOG_DIR/git.stderr" ||
         ! grep -qF 'runtime/p.c' "$TEST_LOG_DIR/git.stderr"; then
        fail_test "$name" 'the expected warning was not produced'
        cat "$TEST_LOG_DIR/git.stderr" >&2
    else
        pass_test "$name"
    fi
}

test_hook_is_tracked_and_executable
test_broken_indent
test_missing_indent
test_broken_isort
test_missing_python_formatters
test_reformats_and_restages_staged_file
test_worktree_clean_after_commit
test_unstaged_file_is_not_committed
test_python_file_is_restaged
test_formatted_file_is_quiet
test_empty_stage
test_partially_staged_file_warns

echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
