{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE field width must be INTEGER }
{ CHECK-FAIL: DECODE precision must be INTEGER }
PROGRAM bad; VAR i: INTEGER; r: REAL; BEGIN r := 1.0; WRITELN(DECODE('1', i:r:'a')) END.
