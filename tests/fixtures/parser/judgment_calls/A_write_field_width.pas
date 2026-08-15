(* judgment: WRITE/WRITELN field-width `:w:d` is standard Pascal but is
   NOT in this grammar's expression_list. Currently accepted. *)
PROGRAM P;
VAR x : REAL;
BEGIN
  WRITELN(x:5:2)
END.
