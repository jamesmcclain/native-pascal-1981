PROGRAM hpx(color, flag, other, addr, output);
{ Program-heading parameters of the manual's extended READFN types
  (13-5..13-7): an enumerated parameter bound by its numeric ordinal
  (the manual reads enumerated values as numbers, not names), BOOLEAN
  parameters bound by identifier name and by number alike, and a pointer
  parameter bound by its numeric address. OUTPUT occupies no argv
  position, so the four bindable parameters map to argv[1..4]. }
TYPE
  hue = (red, green, blue);
VAR
  color: hue;
  flag, other: BOOLEAN;
  addr: ^INTEGER;
BEGIN
  WRITELN('color=', ORD(color));
  WRITELN('flag=', flag);
  WRITELN('other=', other);
  WRITELN('addr=', addr);
END.
