(*$INCLUDE:'unit_interface_forward.inc'*)
PROGRAM UnitInterfaceForward(output);
USES mutualrec;
BEGIN
  WRITELN(IsEven(10));
  WRITELN(IsOdd(10));
  WRITELN(IsEven(7));
  WRITELN(IsOdd(7));
END.
