{ Structural string compatibility is capacity-sensitive: two LSTRING types
  interoperate only when their declared capacities match. A wider-to-narrower
  assignment is still an error, matching the reference ("Cannot assign
  LSTRING(255) to LSTRING(100)"); what is pinned here is the rejection, not
  the phrasing. }
PROGRAM LStringCapacityMismatchRejected(OUTPUT);
TYPE
  Wide = LSTRING(255);
  Narrow = LSTRING(100);
VAR
  w: Wide;
  n: Narrow;
BEGIN
  w := 'x';
  n := w;
  WRITELN(n);
END.
