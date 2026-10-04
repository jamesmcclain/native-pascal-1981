{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
(* should_pass: per-import renaming, USES item ( local ). *)
PROGRAM P;
USES UA (LA), UB (LB);
BEGIN
END.
