(*$INCLUDE:'unit_local_type_shadow.inc'*)
{ codegen's `types` is one flat global table (LookupNamedType scans it whole),
  so a routine-local TYPE cannot shadow an outer one. Accepting this silently
  would lay out `b` with the outer four-element bound and let b[9] write past
  the allocation. }
IMPLEMENTATION OF shadowtype;

TYPE Buf = ARRAY [1..4] OF INTEGER;

PROCEDURE Show;
TYPE Buf = ARRAY [1..9] OF INTEGER;
VAR b: Buf;
BEGIN
  b[9] := 7;
  WRITELN(b[9]);
END;

BEGIN
END.
