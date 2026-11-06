{ DIALECT: vintage }
{ A constant + - * DIV MOD whose value fits the target is checked as one
  constant, so 0 - 32768 is -32768, like -32768 and -(32768). }
PROGRAM constctx(OUTPUT);
CONST W = 32768;
VAR i: INTEGER; v: WORD;
BEGIN
  i := 0 - 32768; WRITELN(i);
  i := 0 - 32768 + 1; WRITELN(i);
  i := 40000 - 10000; WRITELN(i);
  i := 0 - W; WRITELN(i);
  i := -1 - 32767; WRITELN(i);
  v := 65535 - 0; WRITELN(v)
END.
