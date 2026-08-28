(*$INCLUDE:'unit_const_iface_mismatch.inc'*)
{ An IMPLEMENTATION may repeat its own interface's CONST declarations, but the
  repeat has to agree with it. Keeping the interface's value for a differing
  spelling here would compile the unit's two halves against different
  constants without a word. }
IMPLEMENTATION OF mismatchconst;

CONST Limit = 20;

PROCEDURE Show;
BEGIN
  WRITELN(Limit);
END;

BEGIN
END.
