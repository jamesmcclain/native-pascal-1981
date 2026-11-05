PROGRAM write_string_funcs_prec(OUTPUT);
{ Extended string precision limits a written LSTRING function result. }
VAR calls: INTEGER;
FUNCTION F: LSTRING(20);
BEGIN calls := calls + 1; F := 'hello' END;
BEGIN
  calls := 0;
  WRITELN(F::3, '|', F:6:2, '|', F:2:9, '|');
  WRITELN('calls=', calls:1)
END.
