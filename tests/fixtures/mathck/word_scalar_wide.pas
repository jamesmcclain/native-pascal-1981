PROGRAM WordScalarWide;
VAR h8, l8, s8, m8: WORD8;
    h32, l32, s32, m32: WORD32;
    h64, l64, s64, m64: WORD64;
    n8, d8: INTEGER8;
    n32, d32: INTEGER32;
    n64, d64: INTEGER64;
BEGIN
  h8 := 200; l8 := 7; s8 := h8; m8 := 255;
  WRITELN(h8 DIV l8); WRITELN(h8 MOD l8);
  WRITELN(l8 DIV h8); WRITELN(l8 MOD h8);
  WRITELN((h8 > l8) AND (h8 >= l8) AND NOT (h8 < l8) AND NOT (h8 <= l8));
  WRITELN((l8 < h8) AND (l8 <= h8) AND NOT (l8 > h8) AND NOT (l8 >= h8));
  WRITELN((h8 = s8) AND NOT (h8 <> s8) AND (h8 <= s8) AND (h8 >= s8));
  WRITELN((l8 <> h8) AND NOT (l8 = h8) AND (m8 > h8));
  WRITELN(h8 DIV 2); WRITELN(h8 > 1); WRITELN(1 < h8);
  h8 := 14; WRITELN(h8 DIV l8); WRITELN(h8 MOD l8); WRITELN(h8 > l8);
  CASE m8 OF 255: WRITELN('case max'); END;
  h32 := 4000000000; l32 := 7; s32 := h32; m32 := 4294967295;
  WRITELN(h32 DIV l32); WRITELN(h32 MOD l32);
  WRITELN(l32 DIV h32); WRITELN(l32 MOD h32);
  WRITELN((h32 > l32) AND (h32 >= l32) AND NOT (h32 < l32) AND NOT (h32 <= l32));
  WRITELN((l32 < h32) AND (l32 <= h32) AND NOT (l32 > h32) AND NOT (l32 >= h32));
  WRITELN((h32 = s32) AND NOT (h32 <> s32) AND (h32 <= s32) AND (h32 >= s32));
  WRITELN((l32 <> h32) AND NOT (l32 = h32) AND (m32 > h32));
  WRITELN(h32 DIV 2); WRITELN(h32 > 1); WRITELN(1 < h32);
  h32 := 14; WRITELN(h32 DIV l32); WRITELN(h32 MOD l32); WRITELN(h32 > l32);
  CASE m32 OF 4294967295: WRITELN('case max'); END;
  h64 := MAXWORD64; h64 := h64 - 3;
  l64 := 7; s64 := h64; m64 := MAXWORD64;
  WRITELN(h64 DIV l64); WRITELN(h64 MOD l64);
  WRITELN(l64 DIV h64); WRITELN(l64 MOD h64);
  WRITELN((h64 > l64) AND (h64 >= l64) AND NOT (h64 < l64) AND NOT (h64 <= l64));
  WRITELN((l64 < h64) AND (l64 <= h64) AND NOT (l64 > h64) AND NOT (l64 >= h64));
  WRITELN((h64 = s64) AND NOT (h64 <> s64) AND (h64 <= s64) AND (h64 >= s64));
  WRITELN((l64 <> h64) AND NOT (l64 = h64) AND (m64 > h64));
  WRITELN(h64 DIV 2); WRITELN(h64 > 1); WRITELN(1 < h64);
  h64 := 14; WRITELN(h64 DIV l64); WRITELN(h64 MOD l64); WRITELN(h64 > l64);
  CASE m64 OF MAXWORD64: WRITELN('case max'); END;
  { Width promotion must zero-extend the narrower WORD before choosing
    unsigned DIV/MOD and ordering at the promoted width. }
  h8 := 200; h32 := 4000000000;
  WRITELN(h32 DIV h8); WRITELN(h32 MOD h8);
  WRITELN(h8 < h32); WRITELN(h32 > h8);
  n8 := -7; d8 := 2; n32 := -7; d32 := 2; n64 := -7; d64 := 2;
  WRITELN(n8 DIV d8); WRITELN(n8 MOD d8); WRITELN(n8 < d8);
  WRITELN(n32 DIV d32); WRITELN(n32 MOD d32); WRITELN(n32 < d32);
  WRITELN(n64 DIV d64); WRITELN(n64 MOD d64); WRITELN(n64 < d64);
  (* Wide WORD values convert to REAL unsigned too. *)
  WRITELN(FLOAT(m8):6:1); WRITELN(FLOAT(m32):13:1); WRITELN(1.0 + m32:13:1);
  WRITELN(FLOAT(m64):22:1);
END.
