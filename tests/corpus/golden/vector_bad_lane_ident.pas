{ DIALECT: extended }
PROGRAM VectorBadLaneIdent(output);
{ The lane count identifier must name an integer CONST -- an undefined
  name (or a VAR, or a non-integer CONST) is its own diagnostic, distinct
  from the power-of-two range check. Regression guard for a review finding:
  this used to be misreported as "must be a power of two between 2 and 64". }
TYPE
  V = VECTOR [Nope] OF REAL32;
VAR
  v: V;
BEGIN
END.
