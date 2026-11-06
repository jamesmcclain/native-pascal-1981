PROGRAM capat;
{ Exactly 65536 leaves: at the heap-state cap the referent is still
  tracked, so an unset element fails its enabled read. }
TYPE Plane = ARRAY [1..256] OF ARRAY [1..256] OF CHAR;
     PP = ^Plane;
PROCEDURE probe;
VAR p: PP;
BEGIN
  NEW(p); p^[256][256] := 'z'; WRITELN(p^[256][256]);
  {$INITCK+} WRITELN(p^[256][255]) {$INITCK-}
END;
BEGIN probe END.
