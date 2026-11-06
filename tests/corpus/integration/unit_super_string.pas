(*$INCLUDE:'unit_super_string.inc'*)
{ NEW-29: a program passes STRING(n), LSTRING(n) and literal actuals to
  a unit's conformant STRING/LSTRING formals. }
PROGRAM UnitSuperString(output);
USES superstringunit;
VAR
  l: LSTRING(9);
  f: STRING(2);
BEGIN
  f := 'ab';
  Shout(f);
  Shout('literal');
  l := 'xy';
  Grow(l, f);
  Grow(l, 'zz');
  Shout(l);
END.
