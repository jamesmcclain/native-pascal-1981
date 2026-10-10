{ DIALECT: extended }
{ Extended enum READ matches member names case-insensitively, whatever
  case the declaration used, and keeps an enum subrange's lower bound
  for names as well as numbers. }
PROGRAM enum_read_name_case(INPUT, OUTPUT);
TYPE
  day = (mon, Tue, WED, thu, fri);
  wk = Tue..fri;
VAR
  d: day;
  w: wk;
BEGIN
  READ(d);
  WRITELN(ORD(d));
  READ(d);
  WRITELN(ORD(d));
  READ(w);
  WRITELN(ORD(w));
  READ(w);
  WRITELN(ORD(w));
END.
