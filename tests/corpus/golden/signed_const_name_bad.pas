{ DIALECT: vintage extended }
{ Only a numeric CONST name takes a sign. Unary minus on a CHAR (or
  BOOLEAN, enumeration, set or pointer) is a type error: -C used to fold
  to -65 here, and the same minus in a statement aborted codegen. }
PROGRAM signed_const_name_bad(OUTPUT);
CONST
  C = 'A';
  D = -C;
BEGIN
  WRITELN(D, -TRUE)
END.
