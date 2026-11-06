{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: DEVICE code shares the statement parser and needs ";"
   between statements too. *)
DEVICE INTERFACE;
UNIT KERNEL (add);
TYPE vec = ARRAY [1..64] OF INTEGER;
PROCEDURE add (a, b: vec; n: INTEGER);
END;
DEVICE IMPLEMENTATION OF KERNEL;
VAR
  [SPACE(SHARED)] tmp: ARRAY [1..64] OF INTEGER;

PROCEDURE add (a, b: vec; n: INTEGER);
BEGIN
  tmp[1] := 1
  tmp[2] := 2
END;
.
