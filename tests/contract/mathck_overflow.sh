#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# schedule: parallel
# MATHCK O0 guard order: each check precedes its operation.
#
# In the O0 IR of tests/contract/fixtures/mathck/guards.pas
# ({TYPE} = every scalar integer type, both dialects), each checked + - * and
# negation calls one overflow intrinsic at the type's width, extracts its
# overflow bit once in the same block, and ends that block with a branch on
# it to a math.bad block (which calls pas_math_overflow and ends in
# unreachable) or a math.ok block; the result is extracted only in the
# math.ok block. A checked DIV divides only in a math.ok block (signed,
# after the zero and %div.min tests) or a div.ok block (unsigned). The other
# scalar runtime, IR and twin cells are fixtures in tests/contract/mathck_scalar.sh.
# The block walk is an awk pass over the main function: tests/corpus/fixtures.sh
# matches unordered lines and cannot follow a branch to its target block.
fixtures=tests/contract/fixtures/mathck
programs=(vintage:INTEGER:16:0 vintage:WORD:16:1
          extended:INTEGER8:8:0 extended:INTEGER:16:0 extended:INTEGER32:32:0
          extended:INTEGER64:64:0 extended:WORD8:8:1 extended:WORD:16:1
          extended:WORD32:32:1 extended:WORD64:64:1)
declare -A expect=([guards]=10)


# Prints the number of guarded operations; fails on the first violation.
guard_walk='
function strip(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
function fail(m) { print m > "/dev/stderr"; failed = 1; exit 1 }
/^define i32 @main/ { inmain = 1; label = "entry"; nb = 1; order[1] = label; seenlabel[label] = 1; next }
inmain && /^}/ { inmain = 0; next }
inmain {
  if (match($0, /^[-A-Za-z0-9_.]+:/)) {
    label = substr($0, 1, RLENGTH - 1)
    if (!(label in seenlabel)) { seenlabel[label] = 1; order[++nb] = label }
    next
  }
  line = strip($0)
  if (line == "") next
  n[label]++; L[label, n[label]] = line; all = all "\n" line
}
END {
  if (failed) exit 1
  if (nb == 0) fail("no main function")
  for (b = 1; b <= nb; b++) {
    lab = order[b]; cnt = n[lab]
    for (i = 1; i <= cnt; i++) {
      line = L[lab, i]
      if (match(line, /^%[-A-Za-z0-9_.]+ = call \{ i[0-9]+, i1 \} @llvm\.[su](add|sub|mul)\.with\.overflow\.i[0-9]+/)) {
        pair = substr(line, 1, index(line, " = ") - 1)
        bits = substr(line, 1, RLENGTH); sub(/.*\.i/, "", bits)
        if (bits != width) fail(lab ": i" bits " intrinsic, expected i" width)
        flags = 0
        for (j = 1; j <= cnt; j++)
          if (L[lab, j] ~ /^%[-A-Za-z0-9_.]+ = extractvalue / && ends(L[lab, j], " " pair ", 1")) {
            flags++; flag = substr(L[lab, j], 1, index(L[lab, j], " = ") - 1)
          }
        if (flags != 1) fail(lab ": " flags " overflow-bit extracts of " pair)
        branch = L[lab, cnt]; head = "br i1 " flag ", label %"
        rest = substr(branch, length(head) + 1)
        if (index(branch, head) != 1 || rest !~ /^math\.bad[0-9]*, label %math\.ok[0-9]*$/)
          fail(lab ": block ends with " branch)
        bad = rest; sub(/,.*/, "", bad); ok = rest; sub(/.*%/, "", ok)
        call = 0
        for (j = 1; j <= n[bad]; j++) if (index(L[bad, j], "call void @pas_math_overflow(")) call = 1
        if (!call || L[bad, n[bad]] != "unreachable") fail(bad ": no failure call ending in unreachable")
        for (j = 1; j <= cnt; j++) if (ends(L[lab, j], pair ", 0")) fail(lab ": result extracted before the check")
        found = 0
        for (j = 1; j <= n[ok]; j++) if (ends(L[ok, j], pair ", 0")) found = 1
        if (!found) fail(ok ": result of " pair " not extracted")
        seen++
      }
      if (line ~ /= (sdiv|udiv) /) {
        if (unsigned ? lab !~ /^div\.ok/ : lab !~ /^math\.ok/) fail(lab ": division outside its ok block")
        seen++
      }
    }
  }
  if (!unsigned && all !~ /br i1 %div\.min, label %math\.bad[0-9]*, label %math\.ok/)
    fail("no %div.min branch")
  # + - * and negation are intrinsic checks; DIV is one division.
  if (seen != 5) fail(seen " guarded operations, expected 5")
  print seen
}'

guard_unit() { # dialect type width unsigned
  local dialect=$1 type=$2 width=$3 unsigned=$4
  sed "s/{TYPE}/$type/" "$fixtures/guards.pas" > "$dir/guards.pas"
  rm -f "$dir/guards.ll"
  bin/pascal1981 -S --dialect "$dialect" -O0 "$dir/guards.pas" -o "$dir/guards.ll" ||
    die "compile -S guards $dialect $type"
  awk -v width="$width" -v unsigned="$unsigned" "$guard_walk" "$dir/guards.ll" > /dev/null ||
    die "guard order $dialect $type"
  count guards
}

# Independent units run in parallel, each in its own directory and log.
for program in "${programs[@]}"; do
  IFS=: read -r dialect type width unsigned <<< "$program"
  unit "$dialect-$type" guard_unit "$dialect" "$type" "$width" "$unsigned"
done
units_wait
echo "PASS: MATHCK O0 guard order: ${got[guards]} programs, all scalar widths, both dialects"
