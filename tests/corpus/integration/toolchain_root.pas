{ DIALECT: extended }
PROGRAM toolchain_root(input, output);
FUNCTION pas_toolchain_root: ADRMEM [C]; EXTERN;
VAR
  root: ADRMEM;
BEGIN
  root := pas_toolchain_root;
  IF root = NIL THEN
    WRITELN(1)
  ELSE
    WRITELN(0);
END.
