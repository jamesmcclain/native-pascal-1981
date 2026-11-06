#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# STACKCK+ probes host frames and reports main-thread stack overflow; STACKCK- does not.
#
# STACKCK+ gives each host function the LLVM attribute
# "probe-stack"="inline-asm" (stack-clash probing), and a compiland with
# such a function registers the runtime reporter (pas_stackck_init) as a
# module constructor (docs/dialect_notes.md, STACKCK). Checked here:
#  - IR: the setting at each routine's (and the program's) name token
#    decides its attribute; all-off compilands have no probes and no
#    reporter; CPU DEVICE code is probed, NVPTX code never is;
#  - O0 machine code: the probed frame is reserved page by page, the
#    unprobed twin with one stack-pointer adjustment;
#  - runtime, under a reduced stack limit in a subshell, at O0-O3: deep
#    recursion with a 96 KiB frame and one 16 MiB frame each print earlier
#    output, then exactly the STACKCK line, and fail; when they fit the
#    stack they run normally, like their STACKCK- twins;
#  - a SIGSEGV that is not a stack overflow keeps its default action.
# Every run is bounded by `ulimit -s` and a timeout; core dumps are off.
# Fixtures in tests/contract/fixtures/stackck: recurse.pas (depth, index),
# huge.pas (self-call count, index), toggles.pas (per-routine settings).
fixtures=tests/contract/fixtures/stackck
cc=${PASCAL1981_TEST_CC:-${CC:-clang}}
declare -A expect=([ir]=6 [asm]=1 [overflow]=8 [fits]=24 [segv]=1)
error_line='runtime error: STACKCK stack overflow'

# Attribute check: does @name's definition carry "probe-stack"="inline-asm"?
probed() { # file name
  local group
  group=$(sed -n "s/^define .* @$2(.*) \(#[0-9][0-9]*\) {\$/\1/p" "$1")
  [ -n "$group" ] && grep -q "^attributes $group = {.*\"probe-stack\"=\"inline-asm\"" "$1"
}

ir_unit() {
  local f=$fixtures/toggles.pas
  bin/pascal1981 --dialect extended -S "$f" -o "$dir/toggles.ll"
  probed "$dir/toggles.ll" checked || die "toggles: checked not probed"
  probed "$dir/toggles.ll" outer || die "toggles: outer not probed"
  for name in main unchecked inner late; do
    ! probed "$dir/toggles.ll" "$name" || die "toggles: $name probed"
  done
  grep -q '^@llvm.global_ctors = .*@pas_stackck_init' "$dir/toggles.ll" \
    || die "toggles: no reporter constructor"
  count ir
  # Nothing enabled: no probes, no reporter.
  sed 's/{\$STACKCK+}/{$STACKCK-}/g' "$f" > "$dir/off.pas"
  bin/pascal1981 --dialect extended -S "$dir/off.pas" -o "$dir/off.ll"
  ! grep -q 'probe-stack\|pas_stackck_init' "$dir/off.ll" || die "all-off: probes"
  count ir
  # The default is STACKCK+: every routine and main.
  sed 's/{\$STACKCK[+-]}//g' "$f" > "$dir/default.pas"
  bin/pascal1981 --dialect extended -S "$dir/default.pas" -o "$dir/default.ll"
  for name in main checked unchecked outer inner late; do
    probed "$dir/default.ll" "$name" || die "default: $name not probed"
  done
  count ir
  # The recursive large frame of the gap record: only the attribute differs.
  bin/pascal1981 --dialect extended -S "$fixtures/recurse.pas" -o "$dir/on.ll"
  printf '{$STACKCK-}\n' > "$dir/recurse-off.pas"
  cat "$fixtures/recurse.pas" >> "$dir/recurse-off.pas"
  bin/pascal1981 --dialect extended -S "$dir/recurse-off.pas" -o "$dir/rec-off.ll"
  probed "$dir/on.ll" f && probed "$dir/on.ll" main || die "recurse: not probed"
  ! grep -q 'probe-stack\|pas_stackck_init' "$dir/rec-off.ll" || die "recurse-off: probes"
  count ir
  # CPU DEVICE code runs on the host stack: probed. NVPTX: never.
  cp "$ROOT/tests/contract/fixtures/mathck/device_bump/bump.inc" "$dir/"
  sed 's/{FLAG}/-/' "$ROOT/tests/contract/fixtures/mathck/device_bump/bump.impl" > "$dir/bump.impl"
  (cd "$dir" && exec "$ROOT/bin/pascal1981" --dialect extended -S bump.impl -o bump.ll)
  probed "$dir/bump.ll" BUMP || die "CPU DEVICE: BUMP not probed"
  grep -q '^@llvm.global_ctors = .*@pas_stackck_init' "$dir/bump.ll" || die "CPU DEVICE: no reporter"
  count ir
  sed 's/{FLAG}/-/; s/{STATEMENT}/k := 1;/' "$ROOT/tests/contract/fixtures/mathck/device_module.pas" \
    > "$dir/dev.pas"
  bin/pascal1981 --dialect extended --device-triple nvptx64-nvidia-cuda -S "$dir/dev.pas" -o "$dir/dev.ll"
  ! grep -q 'probe-stack\|pas_stackck_init' "$dir/dev.ll" || die "NVPTX: probes"
  count ir
}

asm_unit() {
  # O0 x86-64: the probed frame is touched page by page while it is reserved;
  # the unprobed one is a single adjustment the body then writes beyond.
  bin/pascal1981 --dialect extended -S "$fixtures/recurse.pas" -o "$dir/on.ll"
  printf '{$STACKCK-}\n' > "$dir/off.pas"
  cat "$fixtures/recurse.pas" >> "$dir/off.pas"
  bin/pascal1981 --dialect extended -S "$dir/off.pas" -o "$dir/off.ll"
  for v in on off; do
    "$cc" -O0 -S -w "$dir/$v.ll" -o "$dir/$v.s"
    sed -n '/^f:/,/\.cfi_endproc/p' "$dir/$v.s" > "$dir/$v.f.s"
  done
  grep -qE 'subq[[:space:]]+\$4096, %rsp' "$dir/on.f.s" || die "asm: no page probes"
  ! grep -qE 'subq[[:space:]]+\$4096, %rsp' "$dir/off.f.s" || die "asm: unprobed twin probes"
  count asm
}

build() { # setting opt fixture -> $dir/<fixture><setting>
  local src=$fixtures/$3.pas
  if [ "$1" = - ]; then
    printf '{$STACKCK-}\n' > "$dir/$3-off.pas"
    cat "$src" >> "$dir/$3-off.pas"
    src=$dir/$3-off.pas
  fi
  bin/pascal1981 --dialect extended -O"$2" "$src" -o "$dir/$3$1"
}

run() { # stack-KiB program args... -> status in $status
  status=0
  ( ulimit -c 0; ulimit -s "$1"; shift
    exec timeout 20 "$@" > "$dir/stdout" 2> "$dir/stderr" ) 2> /dev/null || status=$?
}

runtime_unit() { # opt
  local opt=$1 p
  build + "$opt" recurse
  build - "$opt" recurse
  build + "$opt" huge
  build - "$opt" huge
  # Overflow: earlier output survives, then exactly the STACKCK line.
  for p in "recurse+ 1000 5" "huge+ 0 5"; do
    set -- $p
    run 2048 "$dir/$1" "$2" "$3"
    [ "$status" -ne 0 ] || die "O$opt $1: did not fail"
    [ "$status" -ne 124 ] || die "O$opt $1: timed out"
    printf 'start\n' | diff -u - "$dir/stdout" || die "O$opt $1: stdout"
    printf '%s\n' "$error_line" | diff -u - "$dir/stderr" || die "O$opt $1: stderr"
    count overflow
  done
  # The same programs when they fit, checked and unchecked.
  for p in "2048 recurse 3 5 26" "65536 huge 0 5 5" "65536 recurse 100 5 5555"; do
    set -- $p
    for s in + -; do
      run "$1" "$dir/$2$s" "$3" "$4"
      [ "$status" -eq 0 ] || die "O$opt $2$s $3: exit status $status"
      printf 'start\n%s\ndone\n' "$5" | diff -u - "$dir/stdout" || die "O$opt $2$s $3: stdout"
      [ ! -s "$dir/stderr" ] || die "O$opt $2$s $3: stderr"
      count fits
    done
  done
}

segv_unit() {
  # An ordinary NIL store (NILCK-, O0) is not a stack overflow: the
  # reporter declines it and the default action ends the program.
  printf '%s\n' 'PROGRAM wild; {$NILCK-}{$INITCK-}' 'VAR p: ^INTEGER;' \
    "BEGIN WRITELN('start'); p := NIL; p^ := 1; WRITELN('after') END." > "$dir/wild.pas"
  bin/pascal1981 -O0 -S "$dir/wild.pas" -o "$dir/wild.ll"
  grep -q 'pas_stackck_init' "$dir/wild.ll" || die "wild: no reporter"
  bin/pascal1981 -O0 "$dir/wild.pas" -o "$dir/wild"
  run 8192 "$dir/wild"
  [ "$status" -gt 128 ] && [ "$status" -ne 134 ] || die "wild: exit status $status"
  [ ! -s "$dir/stderr" ] || die "wild: stderr"
  count segv
}

unit ir ir_unit
unit asm asm_unit
for opt in 0 1 2 3; do
  unit "runtime-O$opt" runtime_unit "$opt"
done
unit segv segv_unit
units_wait
echo "PASS: STACKCK: ${got[ir]} IR cells (per-routine name-token settings, default," \
  "all-off, CPU DEVICE probed, NVPTX never), ${got[asm]} O0 page-probe cell," \
  "${got[overflow]} overflow cells and ${got[fits]} fitting runs at O0-O3," \
  "${got[segv]} declined SIGSEGV"
