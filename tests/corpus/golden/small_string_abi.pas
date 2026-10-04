PROGRAM small_string_abi;
{$INITCK-}
TYPE ShortText = LSTRING(4); FixedText = STRING(4);
     Wrapped = RECORD text: ShortText END;
VAR s: ShortText; f: FixedText; r: Wrapped;
FUNCTION MakeShort: ShortText;
BEGIN MakeShort := 'abcd' END;
FUNCTION MakeFixed: FixedText;
BEGIN MakeFixed := 'wxyz' END;
FUNCTION Identity(x: ShortText): ShortText;
BEGIN Identity := x END;
FUNCTION Wrap(x: ShortText): Wrapped;
VAR result: Wrapped;
BEGIN result.text := x; Wrap := result END;
FUNCTION Crowded(a,b,c,d,e,f,g: INTEGER; x: ShortText): ShortText;
BEGIN Crowded := x END;
BEGIN
  s := Identity(MakeShort); f := MakeFixed; r := Wrap(s);
  s := Crowded(1,2,3,4,5,6,7,s);
  WRITELN(s); WRITELN(f); WRITELN(r.text)
END.
