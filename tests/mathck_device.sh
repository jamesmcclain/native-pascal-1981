#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# MATHCK in DEVICE code. NVPTX has no host failure path, so an operation
# MATHCK+ would check is a hard compile-time `MATHCK unsupported boundary:
# DEVICE arithmetic at line L column C` with no IR published
# (docs/dialect_notes.md, MATHCK); MATHCK- at the operation is the opt-out,
# and its IR has no overflow intrinsic or `pas_math` call. MATHCK- does not
# waive the mandatory DIV/MOD zero-divisor safety, which DEVICE cannot
# provide. Operations MATHCK does not check (constant folds, WORD ABS, REAL
# arithmetic, TRUNC, ORD) are not boundaries, and a per-statement `{$MATHCK-}`
# opts out only its own operation. CPU DEVICE code shares the host failure
# path, so a kernel launched with LAUNCH traps (MATHCK+) or wraps (MATHCK-)
# like host code, at O0 and O2. Fixtures in tests/fixtures/mathck:
#   device_module.pas, device_enum.pas  NVPTX module templates ({FLAG},
#                                       {STATEMENT}); the statement is on
#                                       line 6 and line 7 respectively
#   device_nvptx.expected               one record per compile: `cell:
#                                       <template> <flag> <statement>`, exit
#                                       status, IR (none/clean/checks), exact
#                                       stderr
#   device_bump/                        CPU DEVICE unit (interface, impl
#                                       template, host) and its outputs
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
ulimit -c 0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
declare -A expect=([rejected]=18 [compiled]=20 [cpu]=4)

die() { echo "FAIL: $*" >&2; exit 1; }
count() { echo "$1" >> "$dir/counts"; }

nvptx_unit() { # every record of device_nvptx.expected, in order
  local cells tpl flag stmt text status ir
  mapfile -t cells < <(sed -n 's/^cell: //p' "$fixtures/device_nvptx.expected")
  [ "${#cells[@]}" -gt 0 ] || die "device_nvptx.expected: no cells"
  : > "$dir/transcript"
  for cell in "${cells[@]}"; do
    read -r tpl flag stmt <<< "$cell"
    text=$(< "$fixtures/$tpl")
    text=${text//'{FLAG}'/"$flag"}
    printf '%s\n' "${text//'{STATEMENT}'/"$stmt"}" > "$dir/dev.pas"
    rm -f "$dir/dev.ll"
    status=0
    bin/pascal1981 --dialect extended --device-triple nvptx64-nvidia-cuda -S \
      "$dir/dev.pas" -o "$dir/dev.ll" 2> "$dir/stderr" || status=nonzero
    if [ ! -s "$dir/dev.ll" ]; then
      ir=none
    elif grep -qE 'with\.overflow|pas_math' "$dir/dev.ll"; then
      ir=checks
    else
      ir=clean
    fi
    { printf 'cell: %s\nstatus: %s\nir: %s\nstderr:\n' "$cell" "$status" "$ir"
      cat "$dir/stderr"
    } >> "$dir/transcript"
    [ "$status" = 0 ] && count compiled || count rejected
  done
  diff -u "$fixtures/device_nvptx.expected" "$dir/transcript" || die "NVPTX cells"
}

cpu_unit() { # flag opt
  local flag=$1 opt=$2 tag status=0
  [ "$flag" = + ] && tag=checked || tag=unchecked
  cp "$fixtures"/device_bump/{bump.inc,main.pas} "$dir/"
  sed "s/{FLAG}/$flag/" "$fixtures/device_bump/bump.impl" > "$dir/bump.impl"
  rm -f "$dir/bump"
  (cd "$dir" && "$root/bin/pascal1981" --dialect extended -O"$opt" \
     main.pas bump.impl -o bump) || die "compile CPU DEVICE MATHCK$flag O$opt"
  # The subshell absorbs bash's own "Aborted" job report.
  (timeout 10 "$dir/bump" > "$dir/stdout" 2> "$dir/stderr"; exit) 2> /dev/null || status=$?
  diff -u "$fixtures/device_bump/$tag.out" "$dir/stdout" || die "CPU MATHCK$flag O$opt: stdout"
  if [ "$flag" = + ]; then
    [ "$status" -ne 0 ] || die "CPU MATHCK+ O$opt: did not fail"
    diff -u "$fixtures/device_bump/checked.err" "$dir/stderr" || die "CPU MATHCK+ O$opt: stderr"
  else
    [ "$status" -eq 0 ] || die "CPU MATHCK- O$opt: exit status $status"
    [ ! -s "$dir/stderr" ] || die "CPU MATHCK- O$opt: stderr"
  fi
  count cpu
}

# Independent units run in parallel, each in its own directory and log.
start() { # name command...
  local name=$1; shift
  dir=$work/$name
  mkdir "$dir"
  ( "$@" && touch "$dir/passed" ) > "$work/$name.log" 2>&1 &
}
start nvptx nvptx_unit
for opt in 0 2; do
  start "cpu-checked-O$opt" cpu_unit + "$opt"
  start "cpu-unchecked-O$opt" cpu_unit - "$opt"
done
wait
failed=0
for log in "$work"/*.log; do
  name=$(basename "$log" .log)
  if [ ! -e "$work/$name/passed" ]; then
    echo "FAIL: unit $name" >&2; cat "$log" >&2; failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
declare -A got=()
while read -r key; do got[$key]=$(( ${got[$key]:-0} + 1 )); done < <(cat "$work"/*/counts)
for key in "${!expect[@]}"; do
  [ "${got[$key]:-0}" -eq "${expect[$key]}" ] ||
    die "$key cells: ${got[$key]:-0}, expected ${expect[$key]}"
done
[ "${#got[@]}" -eq "${#expect[@]}" ] || die "unexpected cell kinds: ${!got[*]}"
echo "PASS: MATHCK DEVICE: $(( got[rejected] + got[compiled] )) NVPTX cells (enabled" \
  "checked operations are located unsupported boundaries with no IR; MATHCK- and" \
  "unchecked operations compile); ${got[cpu]} CPU DEVICE cells trap or wrap through LAUNCH"
