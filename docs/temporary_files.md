# Temporary-file ownership

Project scratch data lives under `/tmp/native-pascal-1981/`. The namespace
must be a real directory owned by the invoking user and not writable by other
users. Creation fails rather than trusting a symlink or unsafe shared root.
Do not clean the namespace wholesale while builds or tests are active.

- The driver allocates a private `driver.*` directory lazily, only when it
  needs intermediate IR/objects. `runtime/temporary.c` records every artifact
  and removes it on normal exit, any error exit, HUP, INT, and TERM. Forked
  children cannot remove their parent's artifacts. Signal cleanup uses only
  async-signal-safe operations. User-selected `-o` outputs are not scratch
  files and retain the driver's existing output policy.
- Anonymous Pascal FILE storage also uses private `file.*` directories in
  this namespace. The file and directory names are removed before the stream
  is returned; the kernel reclaims its anonymous storage on close or process
  death, including fatal signals.
- Shell build/test scripts source `scripts/temp-env.sh` before doing work.
  A supervising shell owns a unique `shell.*` directory and gives the harness
  that directory as `TMPDIR`. It cleans up even if the harness replaces its
  EXIT trap. On a termination signal it terminates and waits for the harness
  process group before removing its workspace. This is a Linux harness and
  requires the existing GNU utilities plus `setsid` (util-linux).
- Python harnesses import `scripts/native_temp.py` before allocating scratch
  files. Each interpreter owns a `python-*` workspace; both `tempfile` and
  child-process `TMPDIR` use it. Context managers still release test-specific
  directories promptly. Exit cleanup also catches otherwise unclaimed scratch
  files (including proxy conformance logs); HUP/TERM become exit exceptions,
  and ordinary INT handling also reaches exit cleanup.
- Emacs mode calls use unique `emacs.*` directories. `unwind-protect` removes
  them on success, Lisp errors, and quits; `kill-emacs-hook` reclaims any
  registered directories on orderly editor termination. Fatal editor crashes
  cannot reliably run Lisp cleanup.
- `SysTempDirCreate` defaults to the project namespace. Its explicit `TMPDIR`
  override is retained as part of this general filesystem API. The caller
  still owns the returned directory and must call `SysRemoveTree`; harnesses
  supply a private parent so abnormal harness termination reclaims it too.

`tests/run.sh` runs every fixture executable in its own private work directory.
File-writing Pascal fixtures use relative filenames. Existing file-valued
`.args` inputs are resolved from the repository before switching directories.
`tests/mathck_twins.sh` likewise gives each fixture/flag/optimization cell a
separate data directory. A shared filename in a shared namespace would still
race; merely changing `/tmp/foo` to `/tmp/native-pascal-1981/foo` is not isolation.

Persistent build outputs remain in `build/`, `bin/`, and `runtime/build/`.
The `test-no-core.so` Makefile recipe intentionally uses a unique same-directory
publication staging file: rename must remain atomic even when `/tmp` and the
repository are on different filesystems. Its EXIT/signal traps remove only
that owned staging file. Benchmark JSON reports in the docs are persistent
outputs in `build/`, not scratch data.

No cleanup mechanism can run after SIGKILL, power loss, or an interpreter's
immediate `_exit`. Any abandoned private directory must be inspected for
ownership/activity before manual removal; never remove other active runs.

Regression coverage: `python3 tests/temp_hygiene.py` (also in `make test-native`)
checks shell/Python/runtime success, failure and HUP/INT/TERM cleanup; fork
ownership; preservation of another active workspace; driver multifile failures
and termination; anonymous runtime storage; pipeline failures; migration
coverage; and 16 parallel copies of `vintage_enum_io`. In a bubblewrap
sandbox with a private `/tmp` (the test is skipped if `bwrap` cannot run), the
driver workspace, anonymous FILE storage, `SysTempDirCreate`, Python, shell and
(when installed) Emacs allocators must each reject a symlinked, group-writable,
other-writable, foreign-owned or non-directory root, and must accept a private
root or create one with mode 0700 even under umask 002. The Emacs ERT suite
also checks nested workspace isolation and cleanup on success, error and quit.
