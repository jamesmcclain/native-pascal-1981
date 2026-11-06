{ DIALECT: vintage extended }
{ CMP-23: NILCK checks the NIL element pointer in l^[i]^.v before the
  field store; the write that would follow never happens. }
PROGRAM SuperPointerSelectNil(OUTPUT);
{$NILCK+}
TYPE
  R = RECORD v: INTEGER END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
VAR
  l: ^SA;
  i: INTEGER;
BEGIN
  NEW(l, 1);
  NEW(l^[0]);
  l^[0]^.v := 5;
  l^[1] := NIL;
  WRITELN('before ', l^[0]^.v:1);
  i := 1;
  l^[i]^.v := 7;
  WRITELN('not reached')
END.
