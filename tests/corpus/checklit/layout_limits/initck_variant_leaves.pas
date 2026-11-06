{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: heap storage at line 16 column 62 }
{ INITCK gives variant alternatives disjoint leaves although their storage
  overlaps, so the leaf count can exceed the byte size: two 1.5 GiB
  alternatives of BOOLEAN leaves fit the layout (1.5 GiB) but have more
  leaves than INTEGER32 counts. Like an ARRAY of that many leaves, the
  record is untracked, so a checked read through the pointer is the
  ordinary unsupported-boundary diagnostic, not a MATHCK trap inside
  codegen. }
(*$INITCK+*)
PROGRAM InitckVariantLeaves;
TYPE Flags = ARRAY [0..32767] OF BOOLEAN;
     Many = ARRAY [0..49151] OF Flags;
     Big = RECORD CASE t: BOOLEAN OF TRUE: (x: Many); FALSE: (y: Many) END;
     P = ^Big;
PROCEDURE Run; VAR p: P; BEGIN NEW(p); p^.t := TRUE; WRITELN(p^.t) END;
BEGIN Run END.
