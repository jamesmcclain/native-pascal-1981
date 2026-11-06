(*$INCLUDE:'units_private_names.pa.inc'*)
(*$INCLUDE:'units_private_names.pb.inc'*)
PROGRAM UnitsPrivateNames(output);
{ Two units each have a private VAR v, VAR Buf, FUNCTION Helper and a
  FORWARD FUNCTION Later; the program declares its own v and Helper too.
  Each compiland's copy is its own (NEW-27): the program links and every
  copy keeps its own value. Shared is exported by pa and is one variable. }
USES pa;
USES pb;
VAR v: INTEGER;
FUNCTION Helper: INTEGER;
BEGIN
  Helper := 100;
END;
BEGIN
  v := Helper;
  Shared := 0;
  WRITELN(GetA, ' ', GetB, ' ', v, ' ', Shared);
  WRITELN(GetA, ' ', GetB, ' ', v, ' ', Shared);
END.
