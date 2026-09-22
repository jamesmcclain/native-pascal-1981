(*$INCLUDE:'aggregate.inc'*)
DEVICE IMPLEMENTATION OF aggregateu;
FUNCTION sum8(v: T8): INTEGER32;
BEGIN sum8 := v.a + v.b END;
FUNCTION sum12(v: T12): INTEGER32;
BEGIN sum12 := v.a + v.b + v.c END;
FUNCTION sum16(v: T16): INTEGER32;
BEGIN sum16 := v.a + v.b + v.c + v.d END;
FUNCTION sum20(v: T20): INTEGER32;
BEGIN sum20 := v.a + v.b + v.c + v.d + v.e END;

FUNCTION ret8: T8;
VAR v: T8;
BEGIN v.a := 1; v.b := 2; ret8 := v END;
FUNCTION ret12: T12;
VAR v: T12;
BEGIN v.a := 1; v.b := 2; v.c := 3; ret12 := v END;
FUNCTION ret16: T16;
VAR v: T16;
BEGIN v.a := 1; v.b := 2; v.c := 3; v.d := 4; ret16 := v END;
FUNCTION ret20: T20;
VAR v: T20;
BEGIN v.a := 1; v.b := 2; v.c := 3; v.d := 4; v.e := 5; ret20 := v END;

PROCEDURE entry8(outp: ADS(GLOBAL) OF BUFFER; v: T8);
BEGIN outp^[8] := sum8(v) END;
PROCEDURE entry12(outp: ADS(GLOBAL) OF BUFFER; v: T12);
BEGIN outp^[9] := sum12(v) END;
PROCEDURE entry16(outp: ADS(GLOBAL) OF BUFFER; v: T16);
BEGIN outp^[10] := sum16(v) END;
PROCEDURE entry20(outp: ADS(GLOBAL) OF BUFFER; v: T20);
BEGIN outp^[11] := sum20(v) END;

PROCEDURE probe(outp: ADS(GLOBAL) OF BUFFER);
VAR
  a8: T8;
  a12: T12;
  a16: T16;
  a20: T20;
  r8: T8;
  r12: T12;
  r16: T16;
  r20: T20;
BEGIN
  a8.a := 1; a8.b := 2;
  a12.a := 1; a12.b := 2; a12.c := 3;
  a16.a := 1; a16.b := 2; a16.c := 3; a16.d := 4;
  a20.a := 1; a20.b := 2; a20.c := 3; a20.d := 4; a20.e := 5;
  outp^[0] := sum8(a8);
  outp^[1] := sum12(a12);
  outp^[2] := sum16(a16);
  outp^[3] := sum20(a20);
  r8 := ret8;
  r12 := ret12;
  r16 := ret16;
  r20 := ret20;
  outp^[4] := r8.a + r8.b;
  outp^[5] := r12.a + r12.b + r12.c;
  outp^[6] := r16.a + r16.b + r16.c + r16.d;
  outp^[7] := r20.a + r20.b + r20.c + r20.d + r20.e
END;
.
