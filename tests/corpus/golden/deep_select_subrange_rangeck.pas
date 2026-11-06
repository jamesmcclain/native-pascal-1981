{ DIALECT: vintage extended }
{ NEW-12: a store into the anonymous subrange element m^[0]^[2] (selector
  depth 4) is range checked against its declared bounds under RANGECK. }
PROGRAM DeepSelectSubrangeRangeck(OUTPUT);
{$RANGECK+}
TYPE
  PS = ^ARRAY [1..2] OF -5..99;
  SS = SUPER ARRAY [0..*] OF PS;
VAR
  m: ^SS;
  i: INTEGER;
BEGIN
  NEW(m, 0);
  NEW(m^[0]);
  i := 99;
  m^[0]^[1] := i;
  WRITELN('in range ', m^[0]^[1]:1);
  i := i + 1;
  m^[0]^[2] := i;
  WRITELN('not reached')
END.
