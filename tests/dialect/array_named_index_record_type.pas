{ A named array index must be ordinal. The typechecker rejects a RECORD
  type name, not just scalar non-ordinals. }
PROGRAM ArrayNamedIndexRecordType(OUTPUT);
TYPE
  R = RECORD
    x: INTEGER;
  END;
VAR
  a: ARRAY [R] OF INTEGER;
BEGIN
END.
