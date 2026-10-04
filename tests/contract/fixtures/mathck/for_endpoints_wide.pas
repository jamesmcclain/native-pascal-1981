PROGRAM ForEndpointsWide;
{ Extended-dialect widths: FOR reaches each type's extreme and stops. }
VAR n: INTEGER;
    i8: INTEGER8; w8: WORD8;
    i32: INTEGER32; w32: WORD32;
    i64, imax, imin: INTEGER64; w64, wmax: WORD64;
BEGIN
  { The WORD64 maximum is not writable as a literal; build it without
    overflow from the largest signed literal. }
  wmax := 9223372036854775807; wmax := wmax + wmax; wmax := wmax + 1;
  { Bounds derived arithmetically: written when INTEGER64 literals of over
    15 digits lost precision (fixed; tests/corpus/golden/literal_int64_exact.pas). }
  imax := 9223372036854775807; imin := -imax - 1;
  n := 0; FOR i8 := 125 TO 127 DO n := n + 1; WRITELN('int8 to max ', n);
  n := 0; FOR i8 := -126 DOWNTO -128 DO n := n + 1; WRITELN('int8 downto min ', n);
  n := 0; FOR w8 := 253 TO 255 DO n := n + 1; WRITELN('word8 to max ', n);
  n := 0; FOR w8 := 126 TO 130 DO n := n + 1; WRITELN('word8 cross sign ', n);
  n := 0; FOR w8 := 2 DOWNTO 0 DO n := n + 1; WRITELN('word8 downto zero ', n);
  n := 0; FOR i32 := 2147483645 TO 2147483647 DO n := n + 1; WRITELN('int32 to max ', n);
  n := 0; FOR i32 := -2147483646 DOWNTO -2147483648 DO n := n + 1; WRITELN('int32 downto min ', n);
  n := 0; FOR w32 := 4294967293 TO 4294967295 DO n := n + 1; WRITELN('word32 to max ', n);
  n := 0; FOR w32 := 2147483646 TO 2147483650 DO n := n + 1; WRITELN('word32 cross sign ', n);
  n := 0; FOR w32 := 4000000000 TO 7 DO n := n + 1; WRITELN('word32 empty ', n);
  n := 0; FOR i64 := imax - 2 TO imax DO n := n + 1; WRITELN('int64 to max ', n);
  n := 0; FOR i64 := imin + 2 DOWNTO imin DO n := n + 1; WRITELN('int64 downto min ', n);
  n := 0; FOR w64 := wmax - 2 TO wmax DO n := n + 1; WRITELN('word64 to max ', n);
  n := 0; FOR w64 := 2 DOWNTO 0 DO n := n + 1; WRITELN('word64 downto zero ', n);
END.
