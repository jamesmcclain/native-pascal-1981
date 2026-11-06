{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: type layout exceeds the supported 2147483647-byte size at line 13 column 7 }
{ An ARRAY whose element is a valid 512 MiB record padded to a stride of
  512 MiB + 1: five of them leave INTEGER32. The array's size is first
  needed by NEW, so the diagnostic names that statement. }
PROGRAM ArrayOfLargeRecords;
TYPE Page = ARRAY [0..32767] OF CHAR;
     Half = ARRAY [0..16383] OF Page;
     Rec = RECORD x: Half; c: CHAR END;
     Five = ARRAY [1..5] OF Rec;
     TP = ^Five;
VAR p: TP;
BEGIN NEW(p) END.
