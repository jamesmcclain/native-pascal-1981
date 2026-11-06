{ DIALECT: extended }
{ NEW-24: in the extended dialect a string capacity may exceed 65535, and
  LOWER and UPPER of it are INTEGER32: UPPER of an LSTRING(70000) printed
  4464 (its low 16 bits). The function-result path is covered at 40000
  in string_bound_types: clang crashes at O0 returning a 70000-byte
  LSTRING by value. }
PROGRAM ExtendedWideStringBounds(OUTPUT);
CONST
  N = 70000;
TYPE
  Huge = LSTRING(N);
VAR
  h: Huge;
  s: STRING(100000);
  k: INTEGER32;

BEGIN
  WRITELN(LOWER(h), ' ', UPPER(h));
  WRITELN(LOWER(s), ' ', UPPER(s));
  k := UPPER(h);
  WRITELN(k);
  k := LOWER(s);
  WRITELN(k)
END.
