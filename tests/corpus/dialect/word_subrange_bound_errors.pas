{ DIALECT: vintage extended }
{ NEW-32: integer subrange bounds are checked by the typechecker. The IBM
  manual (5-7) reads -1..50000 as 65535..50000, so a negative lower bound
  in a WORD subrange is reversed, in the extended dialect too; a bound
  below -32768 is out of range, as for an array bound; a reversed range
  is an error; a WORD subrange is a SET base outside 0..255; and a WORD
  subrange value does not narrow into an INTEGER. }
PROGRAM WordSubrangeBoundErrors;
VAR
  a: -1..50000;
  b: -40000..0;
  c: 5..1;
  s: SET OF 0..40000;
  d: 0..40000;
  i: INTEGER;
BEGIN
  i := d
END.
