(*$INCLUDE:'unit_local_const_shadow.inc'*)
{ codegen's `const_tbl` is one flat global table, so a routine-local CONST
  cannot shadow an outer one -- the IMPLEMENTATION path must diagnose it
  exactly like the PROGRAM path, not quietly keep the outer value. }
IMPLEMENTATION OF shadowconst;

CONST Limit = 10;

PROCEDURE Show;
CONST Limit = 20;
BEGIN
  WRITELN(Limit);
END;

BEGIN
END.
