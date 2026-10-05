{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
(* should_pass: EXTERN is a grammar-listed synonym for EXTERNAL. *)
PROGRAM P;
VAR [EXTERN] x : INTEGER;
BEGIN
END.
