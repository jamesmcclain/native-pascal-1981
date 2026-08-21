{ Native had zero FORWARD-declaration test coverage before this file --
  added alongside the plain-aggregate byval/sret work, which touched the
  FORWARD-declaration reuse path (CodegenRoutineDecl's existing<>0 branch)
  for the first time in a way that could reach an aggregate return. Covers:
  a scalar-returning FORWARD FUNCTION (the baseline shape), mutual
  recursion (the reason FORWARD exists at all), and a FORWARD FUNCTION
  whose return is a byval/sret-classified aggregate. }
PROGRAM ForwardDeclBasic(output);
TYPE
  Str255 = LSTRING(255);

FUNCTION IsEven(n: INTEGER): BOOLEAN; FORWARD;

FUNCTION IsOdd(n: INTEGER): BOOLEAN;
BEGIN
  IF n = 0 THEN IsOdd := FALSE
  ELSE IsOdd := IsEven(n - 1);
END;

FUNCTION IsEven(n: INTEGER): BOOLEAN;
BEGIN
  IF n = 0 THEN IsEven := TRUE
  ELSE IsEven := IsOdd(n - 1);
END;

FUNCTION Greet(n: Str255): Str255; FORWARD;

FUNCTION Greet(n: Str255): Str255;
VAR
  res: Str255;
BEGIN
  res := 'hi ';
  IF n = 'early' THEN
  BEGIN
    Greet := 'early return';
    RETURN;
  END;
  Greet := res;
END;

VAR
  s1, s2: Str255;
BEGIN
  WRITELN(IsEven(4), ' ', IsOdd(4));
  WRITELN(IsEven(7), ' ', IsOdd(7));
  s1 := Greet('bob');
  s2 := Greet('early');
  WRITELN(s1);
  WRITELN(s2);
END.
