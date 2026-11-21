(*$INCLUDE:'unit_const_iface_mismatch_types.inc'*)
{ NEW-34: matching INTERFACE/IMPLEMENTATION CONST restatements are accepted;
  conflicting REAL, STRING, CHAR, ENUM, and type-kind restatements are
  rejected by the typechecker with a source location. }
IMPLEMENTATION OF mismatchconsttypes;

CONST
  OkInt = 10;
  OkReal = 1.5;
  OkStr = 'hello';
  OkChar = 'a';
  OkEnum = Green;
  BadReal = 2.5;
  BadStr = 'world';
  BadChar = 'b';
  BadEnum = Blue;
  BadKind = 10.0;

PROCEDURE Show;
BEGIN
  WRITELN(OkInt);
END;

BEGIN
END.
