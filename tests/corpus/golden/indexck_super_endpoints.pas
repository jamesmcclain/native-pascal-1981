{ DIALECT: extended }
PROGRAM indexck_super_endpoints(OUTPUT);
{ Scalar subscripts through a host descriptor are checked against the
  declared lower (-2) and the actual NEW upper (3). Endpoints read and
  write, a WORD and a WORD64 index stay in bounds, and each subscript
  evaluates its own index expression exactly once. }
TYPE Cells = SUPER ARRAY [-2..*] OF INTEGER; P = ^Cells;
VAR p: P; i: INTEGER; w: WORD; w64: WORD64; evals: INTEGER;
FUNCTION Idx: INTEGER;
BEGIN evals := evals + 1; Idx := 3 END;
BEGIN
  NEW(p, 3);
  p^[-2] := 11; p^[3] := 13;      { constant endpoints }
  i := -2; p^[i] := p^[i] + 1;    { variable endpoints }
  i := 3; p^[i] := p^[i] + 1;
  w := 0; p^[w] := p^[w] + 100;   { unsigned WORD index, in bounds }
  w64 := 1; p^[w64] := 21;        { wide unsigned WORD64 index }
  p^[Idx()] := p^[Idx()] + 1;     { one evaluation per subscript }
  WRITELN(evals, ' ', p^[-2], ' ', p^[0], ' ', p^[1], ' ', p^[3]);
  DISPOSE(p)
END.