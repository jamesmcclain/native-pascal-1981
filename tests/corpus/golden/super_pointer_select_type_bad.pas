{ CMP-23: l^[0]^.v is typed from the record's declaration, so a CHAR
  assigned to the INTEGER field is a located typecheck error, not an
  unknown field and not a codegen failure. }
PROGRAM SuperPointerSelectTypeBad(OUTPUT);
TYPE
  R = RECORD v: INTEGER END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
VAR
  l: ^SA;
BEGIN
  NEW(l, 0);
  NEW(l^[0]);
  l^[0]^.v := 'x'
END.
