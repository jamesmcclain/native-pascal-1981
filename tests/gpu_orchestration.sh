#!/usr/bin/env bash
# Compile and run vector addition through the real CUDA device backend.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cuda_home=${CUDA_HOME:-/usr/local/cuda}
llvm_config=${LLVM_CONFIG:-}

skip() {
  echo "SKIP: GPU orchestration: $1"
  exit 0
}

command -v clang >/dev/null 2>&1 || skip 'clang is not available'
command -v make >/dev/null 2>&1 || skip 'make is not available'
command -v nvidia-smi >/dev/null 2>&1 || skip 'nvidia-smi is not available'
nvidia-smi >/dev/null 2>&1 || skip 'no usable NVIDIA GPU was found'

if [ -z "$llvm_config" ]; then
  llvm_config=$(command -v llvm-config 2>/dev/null ||
                command -v llvm-config-20 2>/dev/null || true)
fi
[ -n "$llvm_config" ] || skip 'llvm-config is not available'
"$llvm_config" --targets-built 2>/dev/null | tr ' ' '\n' |
  grep -qx NVPTX || skip 'LLVM was built without the NVPTX target'

printf '#include <cuda.h>\nint main(void) { return 0; }\n' |
  clang -x c -fsyntax-only -I"$cuda_home/include" - >/dev/null 2>&1 ||
  skip 'CUDA headers are not usable'

[ -x "$root/bin/codegen" ] || skip 'bin/codegen is not executable'

work_dir=$(mktemp -d)
runtime_dir=$(mktemp -d)
trap 'rm -rf "$work_dir" "$runtime_dir"' EXIT

printf 'int main(void) { return 0; }\n' > "$work_dir/cuda_probe.c"
clang "$work_dir/cuda_probe.c" -L"$cuda_home/lib64/stubs" -lcuda \
  -o "$work_dir/cuda_probe" >/dev/null 2>&1 ||
  skip 'libcuda is not linkable'

for source in "$root"/runtime/*; do
  [ -f "$source" ] && cp "$source" "$runtime_dir/"
done
if ! make -C "$runtime_dir" cuda >"$work_dir/runtime.log" 2>&1; then
  skip 'the CUDA runtime shim cannot be built'
fi
runtime_lib="$runtime_dir/build/libpascalrt_cuda.a"
[ -f "$runtime_lib" ] || skip 'the CUDA runtime archive was not produced'

cp "$root/tests/gpu/vadd.typed.json" \
   "$root/tests/gpu/host.typed.json" "$work_dir/"

cd "$work_dir"
env PASCAL_EMIT_PTX=1 \
    PASCAL_DEVICE_TRIPLE=nvptx64-nvidia-cuda \
    "$root/bin/codegen" --dialect extended < vadd.typed.json > vadd.ptx

env PASCAL_DEVICE_BACKEND=cuda \
    "$root/bin/codegen" --dialect extended < host.typed.json > host.ll

cat > dev_ptx_blob.s <<EOF
	.section .rodata
	.globl __pas_device_ptx
__pas_device_ptx:
	.incbin "$work_dir/vadd.ptx"
	.byte 0
EOF
clang -c dev_ptx_blob.s -o dev_ptx_blob.o
clang host.ll dev_ptx_blob.o "$runtime_lib" \
  -L"$cuda_home/lib64/stubs" -lcuda -o vadd-gpu

./vadd-gpu > actual.out
if ! cmp "$root/tests/gpu/host.out" actual.out; then
  echo 'FAIL: GPU vector-add output differs' >&2
  diff -u "$root/tests/gpu/host.out" actual.out >&2 || true
  exit 1
fi

echo 'PASS: GPU vector addition through the CUDA backend'
