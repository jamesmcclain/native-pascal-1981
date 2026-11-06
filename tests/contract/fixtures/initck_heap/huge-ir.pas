{ DIALECT: extended }
PROGRAM hugeir(OUTPUT);
{ Referents above the heap-state leaf cap are untracked: no lookup, no
  registration and no frame-sized fallback, under INITCK- and INITCK+.
  Small keeps the per-site fallback (8 leaves) next to them. }
TYPE Big = ARRAY [0..2147483646] OF CHAR;
     PB = ^Big;
     Row = ARRAY [0..99999] OF CHAR;
     Rows = SUPER ARRAY [0..*] OF Row;
     PR = ^Rows;
     Small = ARRAY [1..8] OF CHAR;
     PSm = ^Small;
PROCEDURE probe(p: PB; r: PR; s: PSm);
BEGIN
  {$INITCK+}
  p^[5] := 'x'; r^[0][7] := 'y'; s^[1] := 'z';
  {$INITCK-}
  WRITELN(p^[5], r^[0][7], s^[1])
END;
VAR p: PB; r: PR; s: PSm;
BEGIN
  NEW(p); NEW(r, 1); NEW(s);
  probe(p, r, s)
END.
