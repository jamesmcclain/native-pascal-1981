{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: record fields are separated by ";". *)
PROGRAM P(OUTPUT);
TYPE R = RECORD
  A: INTEGER
  B: CHAR
END;
BEGIN
END.
