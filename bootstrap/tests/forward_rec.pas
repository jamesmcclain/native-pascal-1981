{ FORWARD mutual recursion, and niladic recursion through a bare name. }
(*$INCLUDE:'testio.inc'*)
PROGRAM forward_rec(input, output);
USES testio;

VAR
  depth: INTEGER;

FUNCTION IsOdd(n: INTEGER32): BOOLEAN; FORWARD;

FUNCTION IsEven(n: INTEGER32): BOOLEAN;
BEGIN
  IF n = 0 THEN
    IsEven := TRUE
  ELSE
    IsEven := IsOdd(n - 1);
END;

FUNCTION IsOdd(n: INTEGER32): BOOLEAN;
BEGIN
  IF n = 0 THEN
    IsOdd := FALSE
  ELSE
    IsOdd := IsEven(n - 1);
END;

FUNCTION CountDown: INTEGER;
BEGIN
  IF depth = 0 THEN
    CountDown := 100
  ELSE
  BEGIN
    depth := depth - 1;
    CountDown := CountDown + 1;
  END;
END;

BEGIN
  WriteLabel('IsEven(10) IsOdd(7) IsEven(3)');
  WriteBool(IsEven(10));
  WRITE(' ');
  WriteBool(IsOdd(7));
  WRITE(' ');
  WriteBool(IsEven(3));
  WRITELN;
  depth := 5;
  WriteLabel('CountDown');
  WriteInt(CountDown);
  WRITELN;
END.
