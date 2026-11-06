{ DIALECT: vintage extended }
{ NEW-12: the inline enumeration behind l^[0]^.color (selector depth 4)
  keeps its identity, so a member of another enumeration is rejected as a
  store, a comparison operand, a CASE label and an array index, and an
  INTEGER store is no narrowing. Each is a located typecheck error. }
PROGRAM DeepSelectEnumBad(OUTPUT);
TYPE
  Other = (x1, x2);
  R = RECORD color: (red, green) END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
VAR
  l: ^SA;
  byother: ARRAY [Other] OF INTEGER;
BEGIN
  NEW(l, 0);
  NEW(l^[0]);
  l^[0]^.color := x1;
  l^[0]^.color := 1;
  IF l^[0]^.color = x2 THEN WRITELN('no');
  CASE l^[0]^.color OF red: WRITELN('r'); x2: WRITELN('x') END;
  byother[l^[0]^.color] := 0
END.
