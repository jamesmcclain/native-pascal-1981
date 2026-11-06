{ DIALECT: vintage extended }
{ CMP-23: the record type recovered for l^[0]^.v is the one the variable's
  declaration named, not a later TYPE of the same name: neither a routine's
  local R that shadows it where the selection is written, nor one left in
  the typechecker's table by an earlier routine. }
PROGRAM SuperPointerSelectScope(OUTPUT);
TYPE
  R = RECORD v: INTEGER END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
VAR
  l: ^SA;

PROCEDURE Earlier;
TYPE
  R = RECORD z: CHAR END;
VAR
  q: R;
BEGIN
  q.z := 'e';
  WRITELN('earlier ', q.z)
END;

PROCEDURE Shadowing;
TYPE
  R = RECORD v: CHAR END;
VAR
  q: R;
BEGIN
  q.v := 's';
  l^[0]^.v := l^[0]^.v + 4;
  WRITELN('shadowing ', q.v, ' ', l^[0]^.v:1)
END;

BEGIN
  Earlier;
  NEW(l, 0);
  NEW(l^[0]);
  l^[0]^.v := 5;
  Shadowing;
  WRITELN('main ', l^[0]^.v:1)
END.
