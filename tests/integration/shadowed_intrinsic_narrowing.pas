{ DIALECT: extended }
PROGRAM ShadowedIntrinsicNarrowing(output);
{ ORD/CHR/SUCC/PRED fold by name in a CONST value -- ParseConstant admits
  those names and nothing else there, so K is 97 whatever ORD means at
  runtime, matching the Python reference. A general expression is the other
  case: both assignments below are ordinary calls to the user's ORD, and the
  narrowing target of the second must not turn it into the folded literal. }
CONST K = ORD('a');
VAR
  x: INTEGER;
  y: INTEGER32;

FUNCTION ORD(c: CHAR): INTEGER;
BEGIN
  ORD := 42;
END;

BEGIN
  WRITELN(K);
  x := ORD('a');
  y := ORD('a');
  WRITELN(x);
  WRITELN(y);
END.
