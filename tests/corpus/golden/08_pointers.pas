PROGRAM PointerTest(OUTPUT);
FUNCTION malloc(size: CINT): ^INTEGER [C]; EXTERN;
PROCEDURE free(p: ^INTEGER) [C]; EXTERN;
VAR
  p: ^INTEGER;
BEGIN
  p := malloc(4);
  p^ := 1234;
  WRITELN('pointer value = ', p^);
  free(p);
END.
