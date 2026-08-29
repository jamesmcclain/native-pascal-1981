{ DIALECT: extended }
PROGRAM wide_int_literals(input, output);
{ An integer literal wider than this dialect's 16-bit INTEGER, in every form
  the language offers, resolved against the target's width.

  This is a regression test for a compiler bug, not a dialect feature: the
  parser read a literal's value with TRUNC, which narrows to INTEGER, so
  40000 became -25536 on its way into the AST and nothing downstream could
  recover it. The reference compiler has always accepted these. }
CONST
  BIG_DEC = 100000;
  BIG_HEX = 16#186A0;
VAR
  n: INTEGER32;
  w: INTEGER64;
BEGIN
  n := 40000;
  WRITELN('dec=', n);
  n := 16#9C40;
  WRITELN('hex=', n);
  n := -70000;
  WRITELN('neg=', n);
  n := BIG_DEC;
  WRITELN('const_dec=', n);
  n := BIG_HEX;
  WRITELN('const_hex=', n);
  n := 100000;
  n := n + 1000000;
  WRITELN('sum=', n);
  w := 5000000000;
  WRITELN('wide=', w);
  { Small literals are unchanged, which is what keeps every existing
    program's generated code byte-identical. }
  n := 32767;
  WRITELN('small=', n);
END.
