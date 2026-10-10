{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM positn_reference_reads;
{$INITCK-}
TYPE Text4 = LSTRING(4); TextPtr = ^Text4;
VAR s, p: Text4; calls: INTEGER; a: ARRAY [1..2] OF Text4;
    r: RECORD text: Text4 END; ptr, other, saved: TextPtr;
FUNCTION Shorten: INTEGER;
BEGIN s := 'xy'; Shorten := 1 END;
FUNCTION Grow: INTEGER;
BEGIN s := 'xxab'; Grow := 1 END;
FUNCTION EmptyPattern: INTEGER;
BEGIN p := ''; EmptyPattern := 7 END;
FUNCTION ChangePattern: Text4;
BEGIN p := 'ab'; ChangePattern := 'ab' END;
FUNCTION Index: INTEGER;
BEGIN calls := calls * 10 + 1; Index := 1 END;
FUNCTION SelectedSource: Text4;
BEGIN calls := calls * 10 + 2; a[1] := 'xy'; SelectedSource := 'xy' END;
FUNCTION Position: INTEGER;
BEGIN calls := calls * 10 + 3; Position := 1 END;
FUNCTION ShortenRecord: INTEGER;
BEGIN r.text := 'xy'; ShortenRecord := 1 END;
FUNCTION Rebind: INTEGER;
BEGIN ptr := other; Rebind := 1 END;
FUNCTION PatternValue: Text4;
BEGIN PatternValue := p END;
FUNCTION ChangePatternOnly: INTEGER;
BEGIN p := 'xy'; ChangePatternOnly := 1 END;
PROCEDURE ByRef(VAR text: Text4);
BEGIN WRITELN(POSITN('ab', text, Shorten)) END;
BEGIN
  s := 'abab'; WRITELN(POSITN('ab', s, Shorten));
  WRITELN(POSITN('ab', s, 1));
  s := 'xy'; WRITELN(POSITN('ab', s, Grow));
  p := 'ab'; s := 'abab'; WRITELN(POSITN(p, s, EmptyPattern));
  p := 'abab'; WRITELN(POSITN(p, ChangePattern(), 1));
  a[1] := 'abab'; calls := 0;
  WRITELN(POSITN(a[Index], SelectedSource(), Position), ' ', calls);
  r.text := 'abab'; WITH r DO WRITELN(POSITN('ab', text, ShortenRecord));
  s := 'abab'; ByRef(s);
  NEW(ptr); NEW(other); ptr^ := 'abab'; other^ := 'xy'; saved := ptr;
  WRITELN(POSITN('ab', ptr^, Rebind));
  DISPOSE(saved); DISPOSE(other);
  p := 'ab'; s := 'abab'; WRITELN(POSITN(PatternValue, s, ChangePatternOnly))
END.
