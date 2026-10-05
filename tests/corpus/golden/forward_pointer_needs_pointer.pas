PROGRAM forward_pointer_needs_pointer(OUTPUT);
{ Only a pointer type may name a type declared later; a record field of
  a later record type is still an unknown type. }
TYPE
  A = RECORD b: B END;
  B = RECORD k: INTEGER END;
VAR x: A;
BEGIN
END.
