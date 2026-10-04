{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
(* WRITE/WRITELN field-width `:w:d` is standard Pascal, accepted although
   it is not an expression_list form. *)
PROGRAM P;
VAR x : REAL;
BEGIN
  WRITELN(x:5:2)
END.
