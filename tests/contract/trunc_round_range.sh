#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# TRUNC/ROUND INTEGER range check (G26): always on, independent of MATHCK.
# IBM 11-6: "Error if ABS(X) > MAXINT". A result outside -32768..32767, or a
# NaN argument, fails with one located `runtime error:` line after flushing
# stdout, under {$MATHCK+} and {$MATHCK-} alike (prepended), both dialects,
# O0-O3. Fixtures under tests/contract/fixtures/mathck:
#   trunc_round_valid.pas/.out      results that fit, including the extremes
#                                   and ROUND's half-away-from-zero ties
#   trunc_round_invalid.pas/.cases  template + one out-of-range call per row
#                                   with its exact diagnostic
#   trunc_round_real32.pas/.err     a REAL32 argument widens first and is
#                                   checked the same way (extended)
#   trunc_round_device/             CPU DEVICE code takes the host failure
#                                   path; NVPTX records the failure in the
#                                   device error cell (IR here; the run is
#                                   in tests/optional/gpu_orchestration.sh)
#                                   and saturates, never poison;
#                                   conv_incl.impl puts the sites in
#                                   included files, which the cell names
#                                   by index (__pas_dev_file_k globals)
#   trunc_round_ir.pas              the range test precedes the conversion:
#                                   fptosi only in conv.ok blocks
# Runtime failure is checked as nonzero, not an exact status.
fixtures=tests/contract/fixtures/mathck
declare -A expect=([valid]=16 [invalid]=128 [real32]=8 [device]=4 [nvptx]=4 [nvinc]=2 [ir]=1)


build() { # dialect opt source exe; never reuse a previous cell's binary
  rm -f "$4"
  bin/pascal1981 --dialect "$1" -O"$2" "$3" -o "$4" ||
    die "compile $3 ($1, O$2)"
}

expect_fail() { # label exe expected-stderr-file: prefix, then the diagnostic
  local status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 5 "$2" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  [ "$status" -ne 0 ] || die "$1: did not fail"
  printf 'prefix\n' | diff -u - "$dir/stdout" || die "$1: stdout"
  diff -u "$3" "$dir/stderr" || die "$1: stderr"
}

valid_unit() { # dialect flag: fitting results, and REAL32 failure (extended)
  local dialect=$1 flag=$2 opt status
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/trunc_round_valid.pas" > "$dir/valid.pas"
  printf '{$MATHCK%s}\n' "$flag" | cat - "$fixtures/trunc_round_real32.pas" > "$dir/real32.pas"
  for opt in 0 1 2 3; do
    build "$dialect" "$opt" "$dir/valid.pas" "$dir/valid"
    status=0
    timeout 5 "$dir/valid" > "$dir/stdout" 2> "$dir/stderr" || status=$?
    [ "$status" -eq 0 ] || die "valid $dialect MATHCK$flag O$opt: exit status $status"
    diff -u "$fixtures/trunc_round_valid.out" "$dir/stdout" ||
      die "valid $dialect MATHCK$flag O$opt: stdout"
    [ ! -s "$dir/stderr" ] || die "valid $dialect MATHCK$flag O$opt: stderr"
    count valid
    [ "$dialect" = extended ] || continue
    build "$dialect" "$opt" "$dir/real32.pas" "$dir/real32"
    expect_fail "REAL32 MATHCK$flag O$opt" "$dir/real32" "$fixtures/trunc_round_real32.err"
    count real32
  done
}

invalid_unit() { # dialect row-number
  local dialect=$1 row=$2 call expected source flag opt
  IFS='|' read -r call expected < <(grep -v '^#' "$fixtures/trunc_round_invalid.cases" |
    sed -n "${row}p")
  [ -n "$call" ] && [ -n "$expected" ] || die "row $row missing"
  printf '%s\n' "$expected" > "$dir/expected"
  source=$(< "$fixtures/trunc_round_invalid.pas")
  source=${source//'{CALL}'/$call}
  for flag in + -; do
    printf '{$MATHCK%s}\n%s\n' "$flag" "$source" > "$dir/bad.pas"
    [ "$(sed -n 7p "$dir/bad.pas")" = "  i := $call; WRITELN(i)" ] || die "line 7: $call"
    for opt in 0 1 2 3; do
      build "$dialect" "$opt" "$dir/bad.pas" "$dir/bad"
      expect_fail "$call $dialect MATHCK$flag O$opt" "$dir/bad" "$dir/expected"
      count invalid
    done
  done
}

device_unit() {
  local value expected opt sat
  cp "$fixtures"/trunc_round_device/conv{.inc,.impl,_incl.impl,_round.inc,_body.inc} "$dir/"
  for value in 1234.6 100000.0; do
    sed "s/{VALUE}/$value/" "$fixtures/trunc_round_device/main.pas" > "$dir/main.pas"
    for opt in 0 2; do
      rm -f "$dir/devhost"
      (cd "$dir" && "$ROOT/bin/pascal1981" --dialect extended -O"$opt" \
         main.pas conv.impl -o devhost) || die "compile DEVICE host $value O$opt"
      if [ "$value" = 1234.6 ]; then
        status=0
        timeout 5 "$dir/devhost" > "$dir/stdout" 2> "$dir/stderr" || status=$?
        [ "$status" -eq 0 ] || die "DEVICE $value O$opt: exit status $status"
        diff -u "$fixtures/trunc_round_device/ok.out" "$dir/stdout" ||
          die "DEVICE $value O$opt: stdout"
        [ ! -s "$dir/stderr" ] || die "DEVICE $value O$opt: stderr"
      else
        expect_fail "DEVICE $value O$opt" "$dir/devhost" "$fixtures/trunc_round_device/fail.err"
      fi
      count device
    done
  done
  # CPU DEVICE fails through the host path, never the device error cell.
  (cd "$dir" && "$ROOT/bin/pascal1981" --dialect extended -O0 -S conv.impl \
     -o cpu.ll) || die "compile CPU DEVICE -S"
  ! grep -qF __pas_dev_error "$dir/cpu.ll" || die "CPU DEVICE: device error cell"
  grep -qF 'call void @pas_conversion_error' "$dir/cpu.ll" ||
    die "CPU DEVICE: no host failure call"
  # NVPTX records a failure in the device error channel (code 1 TRUNC, 2
  # ROUND, claimed by cmpxchg, then line, column and the REAL argument at
  # offsets 4, 8 and 16) and goes on with the saturated value; the CUDA shim
  # fails after the launch. Always on, like the host check: RANGECK- too.
  for opt in 0 2; do
    for rangeck in + -; do
      rm -f "$dir/nvptx.ll"
      printf '(*$INCLUDE:'"'conv.inc'"'*)\n{$RANGECK%s}\n' "$rangeck" > "$dir/nv.impl"
      tail -n +2 "$dir/conv.impl" >> "$dir/nv.impl"
      (cd "$dir" && "$ROOT/bin/pascal1981" --dialect extended -O"$opt" \
         --device-triple nvptx64-nvidia-cuda -S nv.impl -o nvptx.ll) ||
        die "compile NVPTX O$opt RANGECK$rangeck"
      label="NVPTX O$opt RANGECK$rangeck"
      sat=$(grep -oF 'call i16 @llvm.fptosi.sat.i16.f64' "$dir/nvptx.ll" | wc -l || true)
      [ "$sat" -eq 2 ] || die "$label: $sat saturating conversions"
      ! grep -qF 'fptosi double' "$dir/nvptx.ll" || die "$label: fptosi double"
      ! grep -qF pas_conversion_error "$dir/nvptx.ll" || die "$label: host failure call"
      grep -qxF '@__pas_dev_error = addrspace(1) global [3 x i64] zeroinitializer, align 8' \
        "$dir/nvptx.ll" || die "$label: no device error cell"
      for code in 1 2; do
        grep -qE "cmpxchg ptr addrspace\(1\) @__pas_dev_error, i32 0, i32 $code " \
          "$dir/nvptx.ll" || die "$label: no claim of code $code"
      done
      for field in 'i32 6, .* i64 4\)' 'i32 12, .* i64 8\)' 'i32 24, .* i64 8\)' \
                   'double .* i64 16\)'; do
        grep -qE "store $field" "$dir/nvptx.ll" || die "$label: no store $field"
      done
      # Primary-file sites leave the cell's file index (offset 12) zero.
      ! grep -qF __pas_dev_file_ "$dir/nvptx.ll" || die "$label: file name global"
      ! grep -qE 'store i32 .* i64 12\)' "$dir/nvptx.ll" || die "$label: file index store"
      count nvptx
    done
  done
  # Sites in included files: each distinct file is one constant string
  # global, numbered in first-use order, and the claiming thread stores its
  # index at offset 12 (two TRUNC sites share conv_body.inc's index 2).
  for opt in 0 2; do
    rm -f "$dir/nvinc.ll"
    (cd "$dir" && "$ROOT/bin/pascal1981" --dialect extended -O"$opt" \
       --device-triple nvptx64-nvidia-cuda -S conv_incl.impl -o nvinc.ll) ||
      die "compile NVPTX included O$opt"
    label="NVPTX included O$opt"
    grep -qxF '@__pas_dev_file_1 = addrspace(1) constant [15 x i8] c"conv_round.inc\00"' \
      "$dir/nvinc.ll" || die "$label: no file 1 global"
    grep -qxF '@__pas_dev_file_2 = addrspace(1) constant [14 x i8] c"conv_body.inc\00"' \
      "$dir/nvinc.ll" || die "$label: no file 2 global"
    ! grep -qF __pas_dev_file_3 "$dir/nvinc.ll" || die "$label: a third file global"
    grep -qF 'store i32 1, ptr addrspace(1) getelementptr (i8, ptr addrspace(1) @__pas_dev_error, i64 12)' \
      "$dir/nvinc.ll" || die "$label: no file index 1 store"
    [ "$(grep -cF 'store i32 2, ptr addrspace(1) getelementptr (i8, ptr addrspace(1) @__pas_dev_error, i64 12)' \
      "$dir/nvinc.ll")" -ge 2 ] || die "$label: file index 2 stores"
    count nvinc
  done
}

ir_unit() { # every fptosi double sits in a conv.ok* block
  local found calls
  rm -f "$dir/ir.ll"
  bin/pascal1981 -O0 -S "$fixtures/trunc_round_ir.pas" -o "$dir/ir.ll" ||
    die "compile -S trunc_round_ir.pas"
  calls=$(grep -oF 'call void @pas_conversion_error' "$dir/ir.ll" | wc -l || true)
  [ "$calls" -eq 2 ] || die "IR: $calls failure calls"
  found=$(awk '
    { head = $0; sub(/;.*/, "", head); sub(/[ \t]+$/, "", head) }
    head != "" && head !~ /^[ \t]/ && head ~ /:$/ { label = head; next }
    index($0, "fptosi double") {
      if (label !~ /^conv\.ok/) { print "unguarded: " $0 > "/dev/stderr"; exit 1 }
      found++
    }
    END { print found + 0 }' "$dir/ir.ll") || die "IR: fptosi outside conv.ok"
  [ "$found" -eq 2 ] || die "IR: $found conversions"
  count ir
}

# Independent units run in parallel, each in its own directory and log.
rows=$(grep -vc '^#' "$fixtures/trunc_round_invalid.cases")
[ "$rows" -eq 8 ] || die "$rows invalid rows, expected 8"
for dialect in vintage extended; do
  for flag in + -; do
    unit "valid-$dialect$flag" valid_unit "$dialect" "$flag"
  done
  for row in $(seq "$rows"); do
    unit "invalid-$dialect-$row" invalid_unit "$dialect" "$row"
  done
done
unit device device_unit
unit ir ir_unit
units_wait
echo "PASS: TRUNC/ROUND INTEGER range: $(( got[valid] + got[invalid] + got[real32] ))" \
  "runtime cells (${got[valid]} fit, ${got[invalid]} out of range, ${got[real32]} REAL32;" \
  "both dialects, MATHCK+ and MATHCK-, O0-O3); range test before fptosi in IR;" \
  "$(( got[device] + got[nvptx] + got[nvinc] )) DEVICE cells (CPU host failure; NVPTX error cell, RANGECK+ and -," \
  "included-file index)"
