{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: statements in the main program body are separated by ";"
   (NEW-13); the parser once ran two statements together. *)
PROGRAM P(OUTPUT);
BEGIN
  WRITELN('one')
  WRITELN('two')
END.
