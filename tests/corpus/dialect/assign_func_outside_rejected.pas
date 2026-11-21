{ NEW-41: assigning to a function or procedure outside its body is rejected
  in the typechecker rather than failing unlocated in codegen. }
PROGRAM assign_func_outside_rejected;
TYPE
  Pair = RECORD
    a, b: INTEGER;
  END;

FUNCTION Other: INTEGER;
BEGIN
  Other := 1;
END;

FUNCTION MkPair: Pair;
BEGIN
  MkPair.a := 1;
  MkPair.b := 2;
END;

PROCEDURE Sibling;
BEGIN
END;

PROCEDURE P;
BEGIN
  Other := 2;
  MkPair.a := 3;
  Sibling := 4;
END;

BEGIN
  P;
END.
