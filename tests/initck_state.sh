#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# Shadow allocation/reset independently of enabled guards (see initck_scalar.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
{ printf '%s\n' '{$INITCK-}'; tail -n +2 tests/fixtures/initck_state.pas; } > "$work/off.pas"
bin/pascal1981 --dialect extended -O0 -S "$work/off.pas" -o "$work/off.ll" 2> "$work/off.err"
test ! -s "$work/off.err"
# Storage slots: six locals (one a pointer), the INTEGER result, three value formals and the
# private fallback of one tracked VAR formal (it otherwise shares its caller's).
# Value accumulators (initck.taint) and published actual states
# (initck.actual) are per-expression temporaries, not storage, and excluded,
# as is each accepting routine's handshake dummy (initck.noack: supplied_result, recurse and sibling take a tracked formal
# or return a tracked result).
# The predeclared INPUT/OUTPUT TEXT buffers each carry one state byte.
[ "$(grep -E ' = alloca i1,.*' "$work/off.ll" | grep -vc '%file_initck')" -eq 24 ] # b plus 20 metadata plus 3 dummies
[ "$(grep -Ec '%file_initck[0-9]* = alloca i1,' "$work/off.ll")" -eq 2 ]
[ "$(grep -Ec '%initck\.noack[0-9]* = alloca i1,' "$work/off.ll")" -eq 3 ]
[ "$(grep -Ec '%initck\.(taint|actual)[0-9]* = alloca i1,' "$work/off.ll")" -eq 9 ]
# Locals and the result reset false; formals receive their caller's published
# state instead (TRUE when none), never a reset. The VAR formal binds the
# published pointer itself, and its write publishes collected state there.
[ "$(grep -Ec 'store i1 false, ptr %initck\.' "$work/off.ll")" -eq 7 ]
[ "$(grep -Ec 'store i1 false, ptr %initck\.result,' "$work/off.ll")" -eq 1 ]
[ "$(grep -Ec '%initck\.arg[0-9]* = load ptr, ptr .*@pas_initck_args' "$work/off.ll")" -eq 4 ]
grep -Eq '%initck\.alias\.ref = select i1 %[0-9]+, ptr %initck\.alias, ptr %initck\.arg[0-9]*' "$work/off.ll"
grep -Eq 'store i1 %initck\.value[0-9]*, ptr %initck\.alias\.ref,' "$work/off.ll"
# Checking disabled everywhere: no guard or failure call exists.
! grep -Eq '@pas_initck_(error|fail)' "$work/off.ll"
# recurse's x stays tracked although its nested routine declares its own x
# (separate storage). recurse's and sibling's x copy a tracked formal, so they
# publish collected state; the literal writes (b, c, nested x) publish TRUE.
[ "$(grep -Ec 'store i1 true, ptr %initck\.[bcx],' "$work/off.ll")" -eq 3 ]
[ "$(grep -Ec 'store i1 %initck\.value[0-9]*, ptr %initck\.x,' "$work/off.ll")" -eq 2 ]
# Exact names exclude globals, enum/subrange/REAL/wide storage; a plain typed
# pointer's value is one tracked leaf. A record built only from tracked
# scalars gets one leaf per field.
awk '/%initck\..* = alloca/{print $1}' "$work/off.ll" | grep -Ev 'initck\.(taint|actual|noack)' > "$work/names"
printf '%%initck.supplied\n%%initck.result\n%%initck.recvar\n%%initck.p\n%%initck.c\n%%initck.b\n%%initck.x\n%%initck.depth\n%%initck.x\n%%initck.x\n%%initck.alias\n%%initck.supplied\n' > "$work/expected"
diff -u "$work/expected" "$work/names"
# All resets are in entry before any user-value write; no data default was added.
awk '
  /^define / { entry=0 }
  /^entry:/ { entry=1 }
  /^[a-zA-Z_.][a-zA-Z0-9_.]*:/ && !/^entry:/ { entry=0 }
  /store i1 false, ptr %initck\./ { if (!entry) exit 1 }
  /store \[1 x i1\] zeroinitializer, ptr %initck\.recvar/ { if (!entry) exit 1; agg=1 }
  /store i16 0, ptr %x|store i8 0, ptr %c|store i1 false, ptr %b/ { exit 1 }
  END { if (!agg) exit 1 }
' "$work/off.ll"
for target in host nvptx; do
  opts=()
  if [ "$target" = nvptx ]; then opts=(--device-triple nvptx64-nvidia-cuda); fi
  bin/pascal1981 --dialect extended "${opts[@]}" -O0 -S \
    tests/fixtures/initck_state_device.pas -o "$work/device-$target.ll"
  ! grep -q 'initck\.' "$work/device-$target.ll"
done
# Test-only instrumentation inspects initialized metadata, NEVER uninitialized
# Pascal bytes. Poison each freshly reset state and verify simultaneous recursive
# activations have distinct addresses, and later calls reset reused stack slots.
# These injected probes test activation/reset, not the compiler read guards.
awk '
  /^define / { n=0 }
  /store i1 false, ptr %initck\.[a-z_]+,/ && !/%initck\.result,/ {
    slot=$5; sub(/,$/, "", slot); slots[++n]=slot
    print; print "  call void @shadow_enter(ptr " slot ")"; next
  }
  /ret void/ { for (i=n; i>0; --i) print "  call void @shadow_leave(ptr " slots[i] ")" }
  { print }
  END { print "declare void @shadow_enter(ptr)\ndeclare void @shadow_leave(ptr)" }
' "$work/off.ll" > "$work/probed.ll"
cat > "$work/probe.c" <<'EOF'
#include <assert.h>
#include <stdio.h>
static unsigned char *active[64];
static unsigned depth, visits;
void shadow_enter(unsigned char *p) {
    assert(*p == 0);
    for (unsigned i = 0; i < depth; ++i) assert(active[i] != p);
    assert(depth < 64);
    active[depth++] = p;
    ++visits;
    *p = 1;
}
void shadow_leave(unsigned char *p) {
    assert(depth && active[depth - 1] == p && *p == 1);
    --depth;
}
__attribute__((destructor)) static void done(void) {
    assert(depth == 0 && visits == 26);
    puts("shadow activations/reset OK");
}
EOF
for opt in 0 2; do
  clang "-O$opt" "$work/probed.ll" "$work/probe.c" runtime/build/libpascalrt.a -lm -o "$work/probed"
  "$work/probed" > "$work/actual" 2> "$work/err"
  printf 'shadow activations/reset OK\n' > "$work/expected"
  diff -u "$work/expected" "$work/actual"
  test ! -s "$work/err"
done
echo 'PASS: INITCK shadow slots start clear per host scalar-local activation'
