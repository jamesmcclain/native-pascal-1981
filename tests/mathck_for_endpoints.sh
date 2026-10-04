#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/temp-env.sh"
# FOR loops terminate at the final value without stepping past it (G18, G19).
# Iteration counts are the oracle; the post-loop control value is undefined.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fixtures=tests/fixtures/mathck
for dialect in vintage extended; do
  names=(for_endpoints)
  if [[ $dialect == extended ]]; then names+=(for_endpoints_wide); fi
  for name in "${names[@]}"; do
    for flag in + -; do
      printf '{$MATHCK%s}\n' "$flag" > "$work/source.pas"
      cat "$fixtures/$name.pas" >> "$work/source.pas"
      for opt in 0 1 2 3; do
        rm -f "$work/probe" # never rerun a previous cell's binary
        bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/source.pas" -o "$work/probe"
        # A wrapped endpoint would spin forever; the timeout is the failure.
        timeout 5 "$work/probe" > "$work/stdout" 2> "$work/stderr"
        diff -u "$fixtures/$name.out" "$work/stdout"
        test ! -s "$work/stderr"
      done
    done
  done
done
# The subrange-checked path shares the loop shape; keep it terminating too.
cat > "$work/ranged.pas" <<'EOF'
{$RANGECK+}
PROGRAM Ranged;
TYPE Top = 32760..32767; Bottom = -32768..0;
VAR t: Top; b: Bottom; n, lo: INTEGER;
BEGIN
  lo := 32765;
  n := 0; FOR t := lo TO 32767 DO n := n + 1; WRITELN(n);
  n := 0; FOR t := 32767 DOWNTO 32760 DO n := n + 1; WRITELN(n);
  n := 0; FOR b := -32766 DOWNTO -32768 DO n := n + 1; WRITELN(n);
END.
EOF
printf '3\n8\n3\n' > "$work/ranged.expected"
for dialect in vintage extended; do
  for opt in 0 2; do
    rm -f "$work/ranged" # never rerun a previous cell's binary
    bin/pascal1981 --dialect "$dialect" -O"$opt" "$work/ranged.pas" -o "$work/ranged"
    timeout 5 "$work/ranged" > "$work/stdout"
    diff -u "$work/ranged.expected" "$work/stdout"
  done
done
# O0 IR shape: every loop steps through a for_inc block guarded by an equality
# test against the limit, and WORD-family loops compare unsigned.
cat > "$work/shape.pas" <<'EOF'
PROGRAM Shape;
VAR i, lo, hi: INTEGER; w, wlo, whi: WORD; n: INTEGER;
BEGIN
  lo := 1; hi := 3; wlo := 1; whi := 3; n := 0;
  FOR i := lo TO hi DO n := n + 1;
  FOR w := whi DOWNTO wlo DO n := n + 1;
  WRITELN(n);
END.
EOF
bin/pascal1981 --dialect vintage -O0 -S "$work/shape.pas" -o "$work/shape.ll"
test "$(grep -c '^for_inc' "$work/shape.ll")" -eq 2
test "$(grep -c 'icmp eq i16' "$work/shape.ll")" -ge 2
grep -q 'icmp sle i16' "$work/shape.ll"
grep -q 'icmp uge i16' "$work/shape.ll"
if grep -q 'icmp sge i16' "$work/shape.ll"; then
  echo 'WORD DOWNTO loop still compares signed' >&2; exit 1
fi
echo 'PASS: FOR endpoints terminate at the final value, all ordinals/widths, both directives, O0-O3'
