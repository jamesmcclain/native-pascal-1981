{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: type layout exceeds the supported 2147483647-byte size at line 9 column 6 }
{ Each field is 1 GiB, well inside INTEGER32, but the third field's offset
  plus its size is 3 GiB: the record's offset sum, not any one field, leaves
  the layout's INTEGER32 range. Rejected at the RECORD declaration. }
PROGRAM RecordFieldSum;
TYPE Page = ARRAY [0..32767] OF CHAR;
     GiB = ARRAY [0..32767] OF Page;
     Big = RECORD x, y, z: GiB END;
     TP = ^Big;
VAR p: TP;
BEGIN NEW(p) END.
