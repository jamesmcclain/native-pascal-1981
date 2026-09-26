(*$INCLUDE:'unit_forward_pointer.inc'*)
{ A forward pointer type in a unit's INTERFACE, repeated by its
  IMPLEMENTATION, denotes one type in the unit and in the PROGRAM that uses
  it. unit_forward_pointer.host is that PROGRAM. }
IMPLEMENTATION OF fwdlist;

TYPE
  PN = ^N;
  N = RECORD v: INTEGER; nx: PN END;

FUNCTION Count(p: PN): INTEGER;
VAR
  c: INTEGER;
BEGIN
  c := 0;
  WHILE p <> NIL DO
  BEGIN
    c := c + p^.v;
    p := p^.nx;
  END;
  Count := c;
END;

BEGIN
END.
