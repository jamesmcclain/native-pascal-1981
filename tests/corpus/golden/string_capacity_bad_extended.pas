{ DIALECT: extended }
{ The extended dialect raises the capacity limit to the INTEGER32
  maximum, as for an array bound; the lower limits are the same. }
PROGRAM string_capacity_bad_extended(OUTPUT);
CONST N = 3;
TYPE T = LSTRING(-N);
VAR
  a: STRING(-N);
  b: STRING(2147483648);
  c: T;
BEGIN END.
