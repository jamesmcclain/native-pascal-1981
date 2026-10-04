{ DIALECT: extended }
PROGRAM BoundExpressionDynamic(output);
TYPE Data = SUPER ARRAY [2..*] OF INTEGER;
     PData = ^Data;
     Holder = RECORD data: PData END;
     PHolder = ^Holder;
VAR p, q: PData; a: ARRAY [0..1] OF PData;
    holder: Holder; ph: PHolder;
    calls, indexes: INTEGER;
FUNCTION get(n: INTEGER): PData;
BEGIN calls := calls + 1; get := p END;
FUNCTION getholder(n: INTEGER): PHolder;
BEGIN calls := calls + 1; getholder := ph END;
FUNCTION indexof: INTEGER;
BEGIN indexes := indexes + 1; indexof := 1 END;
BEGIN
  NEW(p, 4); NEW(q, 9); a[0] := p; a[1] := q;
  holder.data := q;
  NEW(ph); ph^.data := q;
  WRITELN(LOWER(get(0)^), ' ', calls);
  WRITELN(UPPER(get(0)^), ' ', calls);
  WRITELN(LOWER(a[indexof()]^), ' ', indexes);
  WRITELN(UPPER(a[indexof()]^), ' ', indexes);
  WRITELN(UPPER(holder.data^));
  WRITELN(LOWER(getholder(0)^.data^), ' ', calls);
  WRITELN(UPPER(getholder(0)^.data^), ' ', calls);
  DISPOSE(ph); DISPOSE(q); DISPOSE(p)
END.
