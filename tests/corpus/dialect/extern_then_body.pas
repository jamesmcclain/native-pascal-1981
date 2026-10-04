PROGRAM ExternThenBody(output);

{ EXTERN promises p's body lives in another compiland. Supplying one here is
  not the completion of a placeholder -- that is what FORWARD is for -- so
  this must be rejected. The Python reference already reports "Procedure 'p'
  already declared"; this fixture holds the native compiler to the same rule. }

PROCEDURE p; EXTERN;

PROCEDURE p;
BEGIN
  WRITELN('this body must not be accepted');
END;

BEGIN
  p;
END.
