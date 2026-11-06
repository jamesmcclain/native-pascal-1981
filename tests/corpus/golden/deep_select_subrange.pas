{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-12: anonymous subranges reached at selector depth 4 and 5, below the
  three levels the typechecker's flat metadata keeps: a record field behind
  l^[i]^, an array element m^[i]^[j], and a subrange of an inline
  enumeration. They keep their subrange shape (LOWER and UPPER give the
  declared bounds) and their host type; RANGECK checks in-range stores. }
PROGRAM DeepSelectSubrange(OUTPUT);
{$RANGECK+}
TYPE
  R = RECORD
    small: 1..10;
    letter: 'a'..'f';
    tone: (doh, ray, me, fah, soh);
    top: ray..soh
  END;
  PR = ^R;
  SA = SUPER ARRAY [0..*] OF PR;
  PS = ^ARRAY [1..2] OF -5..99;
  SS = SUPER ARRAY [0..*] OF PS;
VAR
  l: ^SA;
  m: ^SS;
  i: INTEGER;
BEGIN
  NEW(l, 1);
  NEW(l^[0]);
  NEW(l^[1]);
  l^[0]^.small := 10;
  l^[0]^.letter := 'f';
  l^[0]^.tone := fah;
  l^[0]^.top := l^[0]^.tone;
  l^[1]^.small := l^[0]^.small - 9;
  l^[1]^.letter := PRED(l^[0]^.letter);
  l^[1]^.top := SUCC(l^[0]^.top);
  WRITELN(LOWER(l^[0]^.small):1, '..', UPPER(l^[1]^.small):1, ' ',
          LOWER(l^[0]^.letter), '..', UPPER(l^[1]^.letter));
  WRITELN(l^[0]^.small:1, ' ', l^[1]^.small:1, ' ', l^[0]^.letter, l^[1]^.letter,
          ' ', ORD(l^[0]^.top):1, ' ', ORD(l^[1]^.top):1,
          ' ', ORD(UPPER(l^[1]^.top)):1);
  IF l^[1]^.top = soh THEN WRITELN('soh');

  NEW(m, 0);
  NEW(m^[0]);
  i := -5;
  m^[0]^[1] := i;
  m^[0]^[2] := m^[0]^[1] + 104;
  WRITELN(LOWER(m^[0]^[1]):1, '..', UPPER(m^[0]^[2]):1, ' ',
          m^[0]^[1]:1, ' ', m^[0]^[2]:1)
END.
