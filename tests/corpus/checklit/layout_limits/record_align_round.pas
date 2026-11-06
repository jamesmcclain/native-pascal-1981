{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: type layout exceeds the supported 2147483647-byte size at line 11 column 6 }
{ Alignment rounding at the limit: x and y end at exactly 2147483647, a
  valid offset, but the REAL field must start at the next multiple of 8,
  which (x + a - 1) DIV a * a takes past INTEGER32. record_at_limit.pas is
  the same record without the REAL, which fits. }
PROGRAM RecordAlignRound;
TYPE Page = ARRAY [0..32767] OF CHAR;
     Pages = ARRAY [0..65534] OF Page;
     Tail = ARRAY [0..32766] OF CHAR;
     Big = RECORD x: Pages; y: Tail; r: REAL END;
     TP = ^Big;
VAR p: TP;
BEGIN NEW(p) END.
