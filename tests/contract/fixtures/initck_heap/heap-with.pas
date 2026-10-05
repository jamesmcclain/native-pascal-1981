PROGRAM heapwith;
TYPE R = RECORD c1, c2: CHAR END;
     PR = ^R;
PROCEDURE fillc(loc: ADRMEM; len: WORD; val: CHAR); EXTERN;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); WITH p^ DO BEGIN fillc(ADR c1, 2, 'z'); {$INITCK+} WRITELN(c2) {$INITCK-} END END;
BEGIN probe END.
