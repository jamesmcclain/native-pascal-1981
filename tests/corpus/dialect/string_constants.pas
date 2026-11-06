{ DIALECT: vintage extended }
{ NEW-21: a multi-character string CONST is the literal it names (IBM
  5-10): a STRING(n) of its length that converts to LSTRING as needed.
  Declaring one used to stop codegen with "IntLiteralValue: not a foldable
  integer constant", even unused. It assigns, compares, writes and passes
  like the literal; aliases, quote doubling, the empty string, shadowing
  in both directions and a CHAR (one-character) CONST are covered. }
PROGRAM StringConstants(OUTPUT);
CONST
  S = 'abc';
  T = S;
  Q = 'it''s';
  E = '';
  C = 'x';
  N = 7;
  UNUSED = 'never referenced';
TYPE
  S3 = STRING(3);
VAR
  f: S3;
  l: LSTRING(10);
  k: INTEGER;

PROCEDURE ByConst(CONST x: S3);
BEGIN
  WRITELN('const param: ', x)
END;

PROCEDURE ByValue(x: S3);
BEGIN
  WRITELN('value param: ', x)
END;

PROCEDURE ByLString(CONST x: LSTRING);
BEGIN
  WRITELN('lstring param: ', x, ' len ', ORD(x[0]))
END;

FUNCTION Pick: S3;
BEGIN
  Pick := T
END;

PROCEDURE Shadow;
CONST
  N = 'local';
  S = 'xyz';
VAR
  m: LSTRING(8);
BEGIN
  m := N;
  WRITELN('shadow: ', m, ' ', S)
END;

PROCEDURE Outer;
VAR
  S: INTEGER;
BEGIN
  S := 42;
  WRITELN('variable hides constant: ', S)
END;

BEGIN
  f := S;
  WRITELN('fixed: ', f);
  l := T;
  WRITELN('lstring: ', l, ' len ', ORD(l[0]));
  l := Q;
  WRITELN('quote: ', l, ' len ', ORD(l[0]));
  l := E;
  WRITELN('empty: [', l, '] len ', ORD(l[0]));
  WRITELN('char: ', C);
  WRITELN('width: [', S:6, '] [', Q:2, ']');
  IF f = S THEN WRITELN('fixed = S');
  IF f <> Q THEN WRITELN('fixed <> Q');
  l := 'abc';
  IF l = T THEN WRITELN('lstring = T');
  IF l < 'abd' THEN WRITELN('lstring < abd');
  ByConst(S);
  ByValue(T);
  ByLString(Q);
  WRITELN('function: ', Pick);
  Shadow;
  Outer;
  k := N;
  WRITELN('integer constant still: ', k)
END.
