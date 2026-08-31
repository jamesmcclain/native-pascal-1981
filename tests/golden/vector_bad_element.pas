{ DIALECT: extended }
PROGRAM VectorBadElement(output);
{ A vector's element type must be a scalar -- not a RECORD, ARRAY, or
  another VECTOR. }
TYPE
  R  = RECORD x: INTEGER32 END;
  VR = VECTOR [4] OF R;
VAR a: VR;
BEGIN
  a := a
END.
