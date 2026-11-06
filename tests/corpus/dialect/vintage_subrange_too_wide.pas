{ DIALECT: vintage }
{ NEW-32: vintage has no INTEGER32, so an integer subrange bound above
  65535 is an error, as the IBM manual (5-7) says of 0..80000. 0..65535
  is the widest WORD subrange. Codegen used to report these as array
  index bounds. }
PROGRAM VintageSubrangeTooWide;
VAR
  ok: 0..65535;
  a: 0..65536;
  b: 0..80000;
BEGIN
END.
