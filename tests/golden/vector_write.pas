{ DIALECT: extended }
PROGRAM VectorWrite(output);
{ A whole VECTOR is not a writable value (same as a RECORD or ARRAY). }
TYPE V4 = VECTOR [4] OF INTEGER32;
VAR a: V4;
BEGIN
  a := a;
  WRITELN(a)
END.
