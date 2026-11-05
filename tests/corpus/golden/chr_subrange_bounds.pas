{ DIALECT: vintage extended }
{ Subrange and array index bounds may be constant calls (manual 5-9, 6-8):
  CHR(250)..CHR(255) names the non-printable CHAR tail, CHR(K) folds a
  CONST argument, and 'a'..CHR(255) mixes a literal with a call. The
  typechecker and codegen agree on the bounds, so LOWER/UPPER, a FOR over
  the subrange, indexing, a named index type and a SET base all use them. }
PROGRAM chr_subrange_bounds(OUTPUT);
CONST K = 250;
TYPE Tail = CHR(250)..CHR(255);
     FromK = CHR(K)..CHR(255);
     Wide = 'a'..CHR(255);
VAR c: Tail; k: FromK; w: Wide;
    a: ARRAY [CHR(250)..CHR(255)] OF INTEGER;
    n: ARRAY [Tail] OF INTEGER;
    s: SET OF CHR(250)..CHR(252);
    count: INTEGER;
BEGIN
  c := CHR(251); WRITELN(ORD(c));
  k := CHR(250); w := CHR(255); WRITELN(ORD(k), ' ', ORD(w));
  w := 'a'; WRITELN(ORD(w));
  a[CHR(251)] := 7; WRITELN(a[CHR(251)]);
  n[CHR(255)] := 9; WRITELN(n[CHR(255)]);
  WRITELN(ORD(LOWER(a)), ' ', ORD(UPPER(a)), ' ', ORD(LOWER(n)), ' ', ORD(UPPER(n)));
  count := 0;
  FOR c := CHR(250) TO CHR(255) DO count := count + 1;
  WRITELN(count);
  s := [CHR(250), CHR(252)];
  WRITELN(CHR(252) IN s, ' ', CHR(251) IN s);
  WRITELN(ORD(LOWER(s)), ' ', ORD(UPPER(s)))
END.
