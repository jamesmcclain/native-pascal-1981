PROGRAM capover;
{ 65537 leaves: one more than the heap-state cap, so the referent is
  untracked and an enabled read of it is the heap storage boundary. }
TYPE Plane = ARRAY [1..256] OF ARRAY [1..256] OF CHAR;
     R = RECORD a: Plane; b: CHAR END;
     PR = ^R;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); p^.b := 'b'; {$INITCK+} WRITELN(p^.b) {$INITCK-} END;
BEGIN probe END.
