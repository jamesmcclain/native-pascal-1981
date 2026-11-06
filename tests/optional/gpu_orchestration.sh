#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# Compile and run vector addition, the aggregate ABI and the TRUNC/ROUND device error channel on a real CUDA GPU.

cuda_home=${CUDA_HOME:-/usr/local/cuda}
llvm_config=${LLVM_CONFIG:-}

skip_all() { # reason: the host cannot run this suite, which then passes
  skip "GPU orchestration: $1"
  exit 0
}

command -v clang >/dev/null 2>&1 || skip_all 'clang is not available'
command -v make >/dev/null 2>&1 || skip_all 'make is not available'
command -v nvidia-smi >/dev/null 2>&1 || skip_all 'nvidia-smi is not available'
nvidia-smi >/dev/null 2>&1 || skip_all 'no usable NVIDIA GPU was found'
command -v ptxas >/dev/null 2>&1 || skip_all 'ptxas is not available'
compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 |
  tr -d '.[:space:]')
case "$compute_cap" in
  ''|*[!0-9]*) skip_all 'NVIDIA compute capability is not available' ;;
esac
ptx_cpu="sm_$compute_cap"

if [ -z "$llvm_config" ]; then
  llvm_config=$(command -v llvm-config 2>/dev/null ||
                command -v llvm-config-20 2>/dev/null || true)
fi
[ -n "$llvm_config" ] || skip_all 'llvm-config is not available'
"$llvm_config" --targets-built 2>/dev/null | tr ' ' '\n' |
  grep -qx NVPTX || skip_all 'LLVM was built without the NVPTX target'

printf '#include <cuda.h>\nint main(void) { return 0; }\n' |
  clang -x c -fsyntax-only -I"$cuda_home/include" - >/dev/null 2>&1 ||
  skip_all 'CUDA headers are not usable'

[ -x "$ROOT/bin/codegen" ] || skip_all 'bin/codegen is not executable'

runtime_dir=$(mktemp -d)

printf 'int main(void) { return 0; }\n' > "$work/cuda_probe.c"
clang "$work/cuda_probe.c" -L"$cuda_home/lib64/stubs" -lcuda \
  -o "$work/cuda_probe" >/dev/null 2>&1 ||
  skip_all 'libcuda is not linkable'

for source in "$ROOT"/runtime/*; do
  [ -f "$source" ] && cp "$source" "$runtime_dir/"
done
if ! make -C "$runtime_dir" cuda >"$work/runtime.log" 2>&1; then
  skip_all 'the CUDA runtime shim cannot be built'
fi
runtime_lib="$runtime_dir/build/libpascalrt_cuda.a"
[ -f "$runtime_lib" ] || skip_all 'the CUDA runtime archive was not produced'

cp "$ROOT/tests/optional/gpu/vadd.typed.json" \
   "$ROOT/tests/optional/gpu/host.typed.json" "$work/"

compile_typed() (
  cd "$ROOT/tests/optional/gpu"
  "$ROOT/bin/lexer" < "$1" | "$ROOT/bin/parser" --dialect extended |
    "$ROOT/bin/typechecker" --dialect extended
)
compile_typed aggregate.pas > "$work/aggregate.typed.json"
compile_typed aggregate_host.pas > "$work/aggregate_host.typed.json"

cd "$work"
"$ROOT/bin/codegen" --dialect extended --emit-ptx \
    --device-triple nvptx64-nvidia-cuda --ptx-cpu "$ptx_cpu" < vadd.typed.json > vadd.ptx
ptxas -arch="$ptx_cpu" vadd.ptx -o vadd.cubin

"$ROOT/bin/codegen" --dialect extended \
    --device-backend cuda < host.typed.json > host.ll
"$ROOT/bin/codegen" --dialect extended --emit-ptx \
    --device-triple nvptx64-nvidia-cuda --ptx-cpu "$ptx_cpu" < aggregate.typed.json > aggregate.ptx
ptxas -arch="$ptx_cpu" aggregate.ptx -o aggregate.cubin
"$ROOT/bin/codegen" --dialect extended \
    --device-backend cuda < aggregate_host.typed.json > aggregate-host.ll

cat > dev_ptx_blob.s <<EOF
	.section .rodata
	.globl __pas_device_ptx
__pas_device_ptx:
	.incbin "$work/vadd.ptx"
	.byte 0
EOF
clang -c dev_ptx_blob.s -o dev_ptx_blob.o
clang host.ll dev_ptx_blob.o "$runtime_lib" \
  -L"$cuda_home/lib64/stubs" -lcuda -o vadd-gpu

./vadd-gpu > actual.out
if ! cmp "$ROOT/tests/optional/gpu/host.out" actual.out; then
  echo 'FAIL: GPU vector-add output differs' >&2
  diff -u "$ROOT/tests/optional/gpu/host.out" actual.out >&2 || true
  exit 1
fi

echo 'PASS: GPU vector addition through the CUDA backend'

cat > aggregate_ptx_blob.s <<EOF
	.section .rodata
	.globl __pas_device_ptx
__pas_device_ptx:
	.incbin "$work/aggregate.ptx"
	.byte 0
EOF
clang -c aggregate_ptx_blob.s -o aggregate_ptx_blob.o
clang aggregate-host.ll aggregate_ptx_blob.o "$runtime_lib" \
  -L"$cuda_home/lib64/stubs" -lcuda -o aggregate-gpu

./aggregate-gpu > aggregate-actual.out
if ! cmp "$ROOT/tests/optional/gpu/aggregate_host.out" aggregate-actual.out; then
  echo 'FAIL: GPU aggregate ABI output differs' >&2
  diff -u "$ROOT/tests/optional/gpu/aggregate_host.out" aggregate-actual.out >&2 || true
  exit 1
fi

echo "PASS: GPU aggregate ABI through the CUDA backend ($ptx_cpu)"

# NVPTX TRUNC/ROUND device error channel: an out-of-range or NaN conversion
# in a kernel records the first error in __pas_dev_error, and the CUDA shim
# fails the program after the launch with the host check's own diagnostic.
# Cases in tests/optional/gpu/convck.cases; one compiled kernel module.
# kinc's checks are in included files (convck_kinc.inc, convck_kround.inc,
# read from tests/optional/gpu by compile_typed): the report names them
# through the module's __pas_dev_file_k globals.
cp "$ROOT/tests/optional/gpu/convck.inc" "$work/"
compile_typed convck.pas > "$work/convck.typed.json"
"$ROOT/bin/codegen" --dialect extended --emit-ptx \
    --device-triple nvptx64-nvidia-cuda --ptx-cpu "$ptx_cpu" \
    < convck.typed.json > convck.ptx
ptxas -arch="$ptx_cpu" convck.ptx -o convck.cubin
grep -q '__pas_dev_error' convck.ptx ||
  die 'convck.ptx has no device error cell'
grep -q '^.visible .global .align 1 .b8 __pas_dev_file_2\[' convck.ptx ||
  die 'convck.ptx has no visible device file name global'
cat > convck_ptx_blob.s <<EOF
	.section .rodata
	.globl __pas_device_ptx
__pas_device_ptx:
	.incbin "$work/convck.ptx"
	.byte 0
EOF
clang -c convck_ptx_blob.s -o convck_ptx_blob.o
convck_cases=0
while IFS='|' read -r kernel count value expected; do
  case "$kernel" in ''|'#'*) continue ;; esac
  label="$kernel($value) x$count"
  template=$(< "$ROOT/tests/optional/gpu/convck_host.pas")
  template=${template//'{KERNEL}'/$kernel}
  template=${template//'{COUNT}'/$count}
  template=${template//'{VALUE}'/$value}
  if [ "$kernel" = kmany ]; then lines=$((2 * count)); else lines=1; fi
  template=${template//'{LINES}'/$lines}
  printf '%s\n' "$template" > convck_host.pas
  "$ROOT/bin/lexer" < convck_host.pas | "$ROOT/bin/parser" --dialect extended |
    "$ROOT/bin/typechecker" --dialect extended > convck_host.typed.json ||
    die "$label: host front end"
  "$ROOT/bin/codegen" --dialect extended --device-backend cuda \
    < convck_host.typed.json > convck_host.ll || die "$label: host codegen"
  rm -f convck-gpu
  clang convck_host.ll convck_ptx_blob.o "$runtime_lib" \
    -L"$cuda_home/lib64/stubs" -lcuda -o convck-gpu || die "$label: link"
  status=0
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 20 ./convck-gpu > convck.stdout 2> convck.stderr; exit) 2> /dev/null ||
    status=$?
  case "$expected" in
    '!'*)
      [ "$status" -ne 0 ] || die "$label: did not fail"
      printf 'prefix\n' | diff -u - convck.stdout || die "$label: stdout"
      printf '%s\n' "${expected#!}" | diff -u - convck.stderr ||
        die "$label: stderr" ;;
    @*)
      [ "$status" -eq 0 ] || die "$label: exit status $status"
      { echo prefix; cat "$ROOT/tests/optional/gpu/${expected#@}"; } |
        diff -u - convck.stdout || die "$label: stdout"
      [ ! -s convck.stderr ] || die "$label: stderr" ;;
    *)
      [ "$status" -eq 0 ] || die "$label: exit status $status"
      printf 'prefix\n%s\n' "$expected" | diff -u - convck.stdout ||
        die "$label: stdout"
      [ ! -s convck.stderr ] || die "$label: stderr" ;;
  esac
  convck_cases=$((convck_cases + 1))
done < "$ROOT/tests/optional/gpu/convck.cases"
[ "$convck_cases" -eq 21 ] || die "$convck_cases convck cases, expected 21"
echo "PASS: NVPTX TRUNC/ROUND device error channel ($convck_cases cases, $ptx_cpu)"
