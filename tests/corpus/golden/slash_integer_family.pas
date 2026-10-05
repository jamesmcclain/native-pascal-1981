{ DIALECT: vintage }
{ Real division / between INTEGER-family and WORD-family operands and
  literals always produces REAL. }
PROGRAM SlashIntegerFamily(output);
VAR
  w, w2: WORD;
  i: INTEGER;
  r: REAL;
BEGIN
  w := 40000;
  w2 := 4;
  i := 2;

  { Word and integer literals }
  r := w / 1;
  WRITELN(r:0:2);
  r := w / 2;
  WRITELN(r:0:2);
  r := 10 / w2;
  WRITELN(r:0:2);

  { Word and Word }
  r := w / w2;
  WRITELN(r:0:2);

  { Word and Integer }
  r := w / i;
  WRITELN(r:0:2);
  r := i / w2;
  WRITELN(r:0:2);

  { Word assigned to Real }
  r := w;
  WRITELN(r:0:2);

  { Direct write of division expression }
  WRITELN((w / 1):0:2);
  WRITELN((w / w2):0:2);
  WRITELN((w / i):0:2)
END.
