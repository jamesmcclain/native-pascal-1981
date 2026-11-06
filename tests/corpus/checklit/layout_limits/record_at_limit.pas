{ DIALECT: vintage extended }
{ CHECK: @malloc(i64 2147483647) }
{ The largest supported layout: a record of exactly 2147483647 bytes is
  accepted, and NEW allocates all of it (compiled, not run). The same
  record with one more aligned field is record_align_round.pas. }
PROGRAM RecordAtLimit;
TYPE Page = ARRAY [0..32767] OF CHAR;
     Pages = ARRAY [0..65534] OF Page;
     Tail = ARRAY [0..32766] OF CHAR;
     Big = RECORD x: Pages; y: Tail END;
     TP = ^Big;
VAR p: TP;
BEGIN NEW(p); WRITELN(p <> NIL) END.
