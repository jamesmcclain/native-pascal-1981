{ DIALECT: vintage }
{ The vintage dialect has no WORD64: the literal is outside its native
  integer range, as any literal above 65535 is. }
PROGRAM word64_literal_vintage_rejected(OUTPUT);
BEGIN
  WRITELN(18446744073709551615)
END.
