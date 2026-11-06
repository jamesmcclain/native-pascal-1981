{ DIALECT: extended }
{ NEW-29: a conformant STRING/LSTRING formal receives its actual's data
  and UPPER as a Pascal-only pair, which C has no counterpart for, so a
  [C] routine cannot declare one. A STRING(n) formal still can. }
PROGRAM ExtendedSuperStringCFormal(OUTPUT);
PROCEDURE PutS(CONST s: STRING) [C]; EXTERN;
PROCEDURE PutL(VAR s: LSTRING) [C]; EXTERN;
PROCEDURE PutFixed(CONST s: STRING(4)) [C]; EXTERN;
BEGIN
END.
