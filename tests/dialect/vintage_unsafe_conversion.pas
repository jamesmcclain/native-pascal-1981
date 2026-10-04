PROGRAM VintageUnsafeConversion;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR p: PCells; raw: ADRMEM;
BEGIN p := NIL; raw := UNSAFERAW(p) END.
