PROGRAM heapc;
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
PROCEDURE cset(p: PR) [C]; EXTERN;
PROCEDURE probe;
VAR p: PR;
BEGIN NEW(p); cset(p); {$INITCK+} WRITELN(p^.v, ' ', p^.w) {$INITCK-} END;
BEGIN probe END.
