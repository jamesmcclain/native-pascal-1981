PROGRAM untracked;
TYPE R = RECORD a: INTEGER END; P = ^R;
FUNCTION cmem: ADRMEM [C]; EXTERN;
FUNCTION cmem2: ADRMEM [C]; EXTERN;
PROCEDURE Two(VAR x, y: R);
VAR u: INTEGER;
BEGIN {$INITCK-} x.a := u; {$INITCK+} WRITELN(y.a) {$INITCK-} END;
PROCEDURE probe;
VAR p, q: P; ap, aq: ADRMEM;
BEGIN
  NEW(p); NEW(q); p^.a := 2; q^.a := 3; ap := p; aq := q;
  Two(p^, q^);
  p := cmem; q := cmem2; p^.a := 4; q^.a := 5;
  Two(p^, q^);
  {$INITCK+} WRITELN(q^.a) {$INITCK-}
END;
BEGIN probe END.
