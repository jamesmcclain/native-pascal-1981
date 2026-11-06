{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
(* should_pass: ";" separates statements (NEW-13), and an empty statement
   makes doubled, leading and trailing semicolons legal in every statement
   list, as do empty THEN, ELSE, loop, CASE-arm and OTHERWISE statements. *)
PROGRAM P(OUTPUT);
TYPE R = RECORD
  A: INTEGER;
  CASE B: BOOLEAN OF
    TRUE: (C: INTEGER;);
    FALSE: (D: CHAR);
END;
VAR X: INTEGER;
PROCEDURE Q;
BEGIN
END;
PROCEDURE S;
BEGIN
  ;
END;
BEGIN
  ; ;
  X := 1;
  BEGIN END;
  BEGIN ; ; END;
  BEGIN X := 1; END;
  IF X = 1 THEN ELSE X := 2;
  IF X = 1 THEN X := 2 ELSE;
  WHILE FALSE DO;
  REPEAT UNTIL TRUE;
  REPEAT ; UNTIL TRUE;
  REPEAT X := 1; UNTIL TRUE;
  CASE X OF
    1: ;
    2: X := 1;
  END;
  CASE X OF
    1:
  END;
  CASE X OF
    1: X := 2;
    OTHERWISE
  END;
  Q;
  S;
END.
