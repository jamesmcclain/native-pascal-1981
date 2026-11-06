{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: type layout exceeds the supported 2147483647-byte size at line 9 column 6 }
{ One variant alternative's fields sum past 2147483647 bytes: the arm's
  running offset, not the fixed part, leaves INTEGER32. }
PROGRAM RecordVariantArmSum;
TYPE Page = ARRAY [0..32767] OF CHAR;
     GiB = ARRAY [0..32767] OF Page;
     Half = ARRAY [0..16383] OF Page;
     Big = RECORD
             CASE tag: BOOLEAN OF
               TRUE: (x: GiB; y: Half; z: GiB);
               FALSE: (c: CHAR)
           END;
     TP = ^Big;
VAR p: TP;
BEGIN NEW(p) END.
