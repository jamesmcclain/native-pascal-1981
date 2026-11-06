{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: a record's fixed part is separated from its variant part
   by ";". *)
PROGRAM P(OUTPUT);
TYPE R = RECORD
  A: INTEGER
  CASE B: BOOLEAN OF
    TRUE: (C: INTEGER);
    FALSE: (D: CHAR)
END;
BEGIN
END.
