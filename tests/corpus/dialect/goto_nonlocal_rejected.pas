{ DIALECT: vintage extended }
{ NEW-42: a GOTO from a nested routine to an enclosing routine's label (or to
  an undefined label) must be rejected by the typechecker with a source
  location, while a routine-local GOTO in a nested routine stays valid. }
PROGRAM GotoNonlocalRejected;
LABEL 10, outer_done;

PROCEDURE Inner;
LABEL local_lbl;
BEGIN
  GOTO local_lbl;
local_lbl:
  GOTO 10;
  GOTO outer_done;
  GOTO missing_lbl;
END;

BEGIN
  Inner;
10:
outer_done:
END.
