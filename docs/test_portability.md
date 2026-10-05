# Test portability: notes for maintainers and agents

The test suites must pass on any reasonable Linux x86-64 host, not only the
one they were written on. Every rule below comes from a real failure on a
host that differed from the development machine: Ubuntu 22.04 (bash 5.1,
GNU make 4.3) with a source-built LLVM 22 installed outside `/usr`.

## Diagnose before fixing

- **Get the failing output from the failing host.** Do not infer a cause
  from a test name or a summary count. Ask for `./tests/run.sh -v <test>`
  (which prints the expected/actual diff) or the suite's own output, and fix
  what it shows. Guessing cost several rounds of wrong fixes.
- **Check `master` on the same host before blaming a branch.** All of the
  failures above also occurred on `master`; the host had changed, not the
  code.
- **Read the end of `make test`.** It runs every group (`make -k`) and ends
  with a summary of failed targets and `FAIL` lines, keeping the full log in
  `build/test-report.log`. Before that summary existed, failures scrolled by
  and `make test` looked like it had passed.
- **Do not count a passing run on one host as proof for another.** Say which
  host, toolchain and commit a result came from.

## Do not assume the toolchain is quiet

Compilers print harmless text that changes with version and host. Clang 22
warns `-Wgcc-install-dir-libstdcxx` when a newer GCC lacks libstdc++
headers, and warns `-Woverride-module` when its default triple differs only
in vendor from the IR's.

- A test may require *our* stages to print nothing, never the host C
  compiler or linker. Under `scripts/test-env.sh` the driver compiles
  through `scripts/test-cc.sh`, which drops clang's warning lines; keep new
  empty-stderr checks behind that, or check `-S` output (stages only).
- Do not build C helpers with `-Werror`. A new compiler's new warning then
  fails the suite, although nothing in the repository changed. Use the
  Makefile's `-Wall -Wextra`.
- Respect `CC`/`PASCAL1981_CC` instead of hard-coding `clang`.

## Do not silence a test failure by changing the compiler

Fix the test's assumption, not the product. Passing
`--target=x86_64-pc-linux-gnu` from the driver silenced `-Woverride-module`
but broke every link on a clang that installs its runtime under its default
triple (`lib/clang/22/lib/x86_64-unknown-linux-gnu/libclang_rt.builtins.a`).
Likewise, adding `-Wno-...` options to the driver hides real host problems
from users. Change the driver only for a user-visible defect, and then
consider every way clang can be installed.

## Do not assume tool versions

- **bash.** bash 5.3 replaces a `( cd dir && prog )` subshell with `prog`;
  bash 5.1 forks it, and when `prog` aborts the subshell writes
  `... Aborted ...` into any stderr it captures. Write `exec prog` in such
  subshells, or discard the shell's own report (`{ prog; } 2>/dev/null`).
- **GNU make.** make 4.3 deletes a file reached only through pattern rules
  as an intermediate; make 4.4 keeps it. Name every built artifact that a
  test runs as an explicit target.
- **LLVM IR text.** New LLVM versions add attributes and change printing
  (`nocreateundeforpoison` contains both `undef` and `poison`). Match whole
  words or parsed instructions, never bare substrings, and avoid depending
  on attribute lists or metadata numbering.

## Do not assume optional tools exist

Probe for `bwrap`, `curl`, `emacs`, `jq` and the like with `command -v` /
`shutil.which` and skip with a stated reason when one is missing or cannot
run. A crash on a missing tool reads as a test failure. Document the
recommended packages in `README.md` (bubblewrap is one).

## Checklist for a new or changed test

- Does it pass if the C compiler prints warnings?
- Does it depend on the shell, make or LLVM version, or on IR formatting?
- Does it run any host tool that might be missing?
- Does a failure print enough (a diff, the command) to diagnose it remotely?
