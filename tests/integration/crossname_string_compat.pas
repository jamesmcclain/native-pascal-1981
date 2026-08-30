PROGRAM CrossNameStringCompat(output);
{ Structurally identical, differently named string types of equal capacity
  are interchangeable in codegen -- assignment, VAR parameter and value
  parameter -- matching the reference type system. This is what lets
  jsonutil's Str255, bytebuf's ByteStr and argparse's ArgStr (all
  LSTRING(255)) interoperate without a hand-written character copy. }
TYPE
  AStr = LSTRING(255);
  BStr = LSTRING(255);
  SFix = STRING(10);
  TFix = STRING(10);
VAR
  a: AStr;
  b: BStr;
  s: SFix;
  t: TFix;

PROCEDURE TakeVar(VAR x: BStr);
BEGIN
  WRITELN('var:', x);
END;

PROCEDURE TakeVal(x: BStr);
BEGIN
  WRITELN('val:', x);
END;

BEGIN
  a := 'hello';
  b := a;                { cross-named LSTRING assignment }
  WRITELN('assign:', b);
  TakeVar(a);            { AStr passed to a VAR BStr parameter }
  TakeVal(a);            { AStr passed to a value BStr parameter }
  s := 'tuppens_wo';
  t := s;                { cross-named fixed STRING assignment }
  WRITELN('sfix:', t);
END.
