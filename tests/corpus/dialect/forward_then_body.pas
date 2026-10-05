PROGRAM ForwardThenBody(output);

{ The legal neighbour of extern_then_body: FORWARD declares p so q can call
  it before its body appears, and the later body completes the placeholder.
  This must keep working -- the EXTERN rule has to be narrow enough to leave
  it alone. }

PROCEDURE p; FORWARD;

PROCEDURE q;
BEGIN
  p;
END;

PROCEDURE p;
BEGIN
  WRITELN('forward then body');
END;

BEGIN
  q;
END.
