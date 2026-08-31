{ A routine declared inside another routine. Lowering the inner one used to
  leave the builder pointing at the program's own main function, so the rest
  of the OUTER body -- its statements and its closing ret -- was emitted into
  main, main got a `ret void` it had no type for, and the outer function's
  entry block was left unterminated ("Broken module found"). Two levels deep,
  plus an inner routine called after the nested declarations, so the restored
  position has to be the enclosing routine's block and not the program's.

  Note what this does NOT test: an inner routine reading an enclosing
  ROUTINE's local (uplevel access). Neither compiler implements a static
  link, so the inner routines here touch only their own parameters and file-
  level variables. }
PROGRAM NestedRoutines(output);
VAR
  acc: INTEGER;

PROCEDURE Outer(n: INTEGER);

  FUNCTION Twice(v: INTEGER): INTEGER;

    FUNCTION Plus1(v: INTEGER): INTEGER;
    BEGIN
      Plus1 := v + 1
    END;

  BEGIN
    Twice := Plus1(v) * 2
  END;

  PROCEDURE Bump;
  BEGIN
    acc := acc + 100
  END;

BEGIN
  acc := Twice(n);
  Bump
END;

BEGIN
  Outer(3);
  WRITELN(acc);
  Outer(5);
  WRITELN(acc)
END.
