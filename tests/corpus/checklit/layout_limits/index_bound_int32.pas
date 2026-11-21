{ DIALECT: extended }
{ CHECK-FAIL: Subrange upper bound is above 2147483647 at line 6 column 6 }
{ An index bound above INTEGER32 used to be saturated to 2147483647 on the
  way in, silently giving the array a different range. }
PROGRAM IndexBoundInt32;
TYPE W = ARRAY [40000..4294967295] OF CHAR;
     TP = ^W;
VAR p: TP;
BEGIN p := NIL END.
