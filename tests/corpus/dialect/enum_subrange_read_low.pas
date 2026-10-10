{ DIALECT: vintage extended }
{ A READ into an enum subrange accepts only the subrange's ordinals, even
  with RANGECK off: 0 (MON) is below TUE..FRI and is rejected by the
  reader itself, not stored. }
PROGRAM enum_subrange_read_low(INPUT, OUTPUT);
{$RANGECK-}
TYPE
  day = (mon, tue, wed, thu, fri);
  wk = tue..fri;
VAR
  d: wk;
BEGIN
  READ(d);
  WRITELN(ORD(d));
  READ(d);
  WRITELN(ORD(d));
  READ(d);
  WRITELN('unreachable ', ORD(d));
END.
