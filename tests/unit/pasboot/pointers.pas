{ ADRMEM and typed pointers are mutually assignable; pointer + integer
  strides by the pointee size (one byte for ADRMEM and ^CHAR); ADR passes
  a local as a C out-parameter. }
(*$INCLUDE:'testio.inc'*)
PROGRAM pointers(input, output);
USES testio;

TYPE
  Pair = RECORD
    key: INTEGER32;
    tag: CHAR;
  END;
  PPair = ^Pair;
  PInt = ^INTEGER32;

FUNCTION malloc(size: CSIZE_T): ADRMEM [C]; EXTERN;
PROCEDURE free(ptr: ADRMEM) [C]; EXTERN;
FUNCTION strtol(s: ADRMEM; endp: ADRMEM; base: CINT): CLONG [C]; EXTERN;

VAR
  raw, endp, digits: ADRMEM;
  pi, qi: PInt;
  pc: ^CHAR;
  pp: PPair;
  i: INTEGER32;
  n: CLONG;

BEGIN
  raw := malloc(64);
  pi := raw;
  FOR i := 0 TO 3 DO
  BEGIN
    qi := pi + i;
    qi^ := i * 100;
  END;
  pc := raw;
  pc := pc + 4;
  WriteLabel('byte 4 is the low byte of 100');
  WriteInt(ORD(pc^));
  WRITELN;
  qi := raw + 12;
  WriteLabel('ADRMEM + 12 as ^INTEGER32');
  WriteInt(qi^);
  WRITELN;
  pp := raw;
  pp := pp + 1;
  pp^.key := 42;
  pp^.tag := 'q';
  qi := raw + SIZEOF(Pair);
  WriteLabel('record stride = SIZEOF');
  WriteInt(qi^);
  WRITE(' ');
  WRITE(pp^.tag);
  WRITELN;
  WriteLabel('pointer equality');
  WriteBool(qi = pi + 2);
  WRITE(' ');
  WriteBool(pp <> NIL);
  WRITELN;
  digits := raw + 32;
  pc := digits;
  pc^ := '7';
  pc := pc + 1;
  pc^ := '3';
  pc := pc + 1;
  pc^ := 'x';
  pc := pc + 1;
  pc^ := CHR(0);
  n := strtol(digits, ADR endp, 10);
  WriteLabel('strtol');
  WriteInt(n);
  WRITE(' ');
  pc := endp;
  WRITE(pc^);
  WRITELN;
  free(raw);
END.
