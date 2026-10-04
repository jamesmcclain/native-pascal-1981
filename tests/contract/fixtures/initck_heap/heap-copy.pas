PROGRAM heapcopy;
TYPE Pair = RECORD a, b: INTEGER END;
     PP = ^Pair;
PROCEDURE probe;
VAR p, q: PP;
BEGIN
  NEW(p); NEW(q);
  {$INITCK-} p^.a := 4; q^ := p^; {$INITCK+}
  WRITELN(q^.a)
  {$INITCK-}
END;
BEGIN probe END.
