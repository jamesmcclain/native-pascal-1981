(* REAL argument to WRD is invalid (type error), not a parser error. Rejection handled by type checker -- see test_typecheck.py::TestWrdByword *)
PROGRAM WrdRealArg;
VAR
    w : WORD;
    x : REAL;
BEGIN
    x := 3.14;
    w := WRD(x)   (* ERROR: REAL is not an ordinal type *)
END.
