{ DIALECT: extended }
PROGRAM VectorTypes;
TYPE
  V4F = VECTOR [4] OF REAL32;
  V8I = VECTOR [8] OF INTEGER32;
  M4  = VECTOR [4] OF BOOLEAN;
  M8  = VECTOR [8] OF BOOLEAN;
  V4D = VECTOR [4] OF REAL;
VAR
  a, b: V4F;
  iv, iw, ix: V8I;
  m, m2: M4;
  mk: M8;
  d, e, f: V4D;
  i: INTEGER;
BEGIN
  { M0: declare, whole-vector assign, SIZEOF, LOWER/UPPER. }
  a := b;
  b := a;
  iw := iv;
  m := m;
  WRITELN(SIZEOF(V4F));
  WRITELN(SIZEOF(a));
  WRITELN(SIZEOF(V8I));
  WRITELN(SIZEOF(M4));
  WRITELN(SIZEOF(b));
  WRITELN(LOWER(a), ' ', UPPER(a));
  WRITELN(LOWER(iv), ' ', UPPER(iv));
  WRITELN(LOWER(m), ' ', UPPER(m));

  { M2a: lane write then read, every lane, for a float, an integer and a
    mask vector; a variable lane index (unchecked) and a lane-to-lane
    assignment. }
  FOR i := 0 TO 3 DO d[i] := (i + 1) * 1.5;
  FOR i := 0 TO 3 DO WRITELN('d[', i, ']=', d[i]:0:2);
  WRITELN('d1+d3=', (d[1] + d[3]):0:2);

  FOR i := 0 TO 7 DO iv[i] := i * i;
  FOR i := 0 TO 7 DO WRITE(iv[i], ' ');
  WRITELN;
  iv[7] := iv[0] + iv[3];
  WRITELN('iv7=', iv[7]);

  m[0] := TRUE;
  m[1] := FALSE;
  m[2] := TRUE;
  m[3] := FALSE;
  FOR i := 0 TO 3 DO
    IF m[i] THEN WRITE('T ') ELSE WRITE('F ');
  WRITELN;

  { M2b: VSPLAT -- constant scalar (folds to a splat constant), runtime
    scalar (insertelement + zero-mask shufflevector), and a BOOLEAN mask. }
  d := VSPLAT(2.5, V4D);
  FOR i := 0 TO 3 DO WRITE(d[i]:0:2, ' ');
  WRITELN;
  d := VSPLAT(d[0] + 0.5, V4D);
  FOR i := 0 TO 3 DO WRITE(d[i]:0:2, ' ');
  WRITELN;
  iv := VSPLAT(9, V8I);
  WRITELN(iv[0], ' ', iv[7]);
  m := VSPLAT(TRUE, M4);
  FOR i := 0 TO 3 DO
    IF m[i] THEN WRITE('T ') ELSE WRITE('F ');
  WRITELN;

  { M1: elementwise arithmetic and logic. Both operands are the identical
    VECTOR type -- no scalar promotion (VSPLAT fills the constant vectors).
    One representative lane is printed per operator. }
  e := VSPLAT(2.0, V4D);
  f := VSPLAT(3.0, V4D);
  d := e + f;   WRITELN('f+ ', d[0]:0:2);
  d := f - e;   WRITELN('f- ', d[0]:0:2);
  d := e * f;   WRITELN('f* ', d[0]:0:2);
  d := f / e;   WRITELN('f/ ', d[0]:0:2);
  d := -e;      WRITELN('f- ', d[0]:0:2);

  iv := VSPLAT(10, V8I);
  iw := VSPLAT(3, V8I);
  ix := iv + iw;    WRITELN('i+ ', ix[0]);
  ix := iv - iw;    WRITELN('i- ', ix[0]);
  ix := iv * iw;    WRITELN('i* ', ix[0]);
  ix := iv DIV iw;  WRITELN('idiv ', ix[0]);
  ix := iv MOD iw;  WRITELN('imod ', ix[0]);
  ix := iv AND iw;  WRITELN('iand ', ix[0]);
  ix := iv OR iw;   WRITELN('ior ', ix[0]);
  ix := iv XOR iw;  WRITELN('ixor ', ix[0]);
  ix := -iv;        WRITELN('ineg ', ix[0]);
  ix := NOT iv;     WRITELN('inot ', ix[0]);

  m := VSPLAT(TRUE, M4);
  m2 := VSPLAT(FALSE, M4);
  m := m AND m2;  IF m[0] THEN WRITELN('m& T') ELSE WRITELN('m& F');
  m := VSPLAT(TRUE, M4);
  m := m OR m2;   IF m[0] THEN WRITELN('m| T') ELSE WRITELN('m| F');
  m := NOT m2;    IF m[0] THEN WRITELN('m! T') ELSE WRITELN('m! F');

  { M3: horizontal reductions. VSUM/VPROD/VMIN/VMAX to a scalar element,
    VANY/VALL over a mask to a BOOLEAN. Float VSUM/VPROD are ordered. }
  FOR i := 0 TO 3 DO e[i] := (i + 1) * 1.0;   { 1 2 3 4 }
  WRITELN('fsum ', VSUM(e):0:2);
  WRITELN('fprod ', VPROD(e):0:2);
  WRITELN('fmin ', VMIN(e):0:2);
  WRITELN('fmax ', VMAX(e):0:2);

  FOR i := 0 TO 7 DO ix[i] := i - 3;          { -3 .. 4 }
  WRITELN('isum ', VSUM(ix));
  WRITELN('imin ', VMIN(ix));
  WRITELN('imax ', VMAX(ix));
  ix := VSPLAT(2, V8I);
  WRITELN('iprod ', VPROD(ix));

  m[0] := TRUE; m[1] := FALSE; m[2] := FALSE; m[3] := FALSE;
  IF VANY(m) THEN WRITELN('any T') ELSE WRITELN('any F');
  IF VALL(m) THEN WRITELN('all T') ELSE WRITELN('all F');
  m2 := VSPLAT(TRUE, M4);
  IF VALL(m2) THEN WRITELN('all2 T') ELSE WRITELN('all2 F');

  { M4: lanewise comparison -> a BOOLEAN mask, then VANY/VALL and VSELECT. }
  FOR i := 0 TO 7 DO iv[i] := i;        { 0 1 2 3 4 5 6 7 }
  iw := VSPLAT(4, V8I);
  mk := iv < iw;                        { T T T T F F F F }
  IF VANY(mk) THEN WRITELN('cany T') ELSE WRITELN('cany F');
  IF VALL(mk) THEN WRITELN('call T') ELSE WRITELN('call F');
  FOR i := 0 TO 7 DO
    IF mk[i] THEN WRITE('T ') ELSE WRITE('F ');
  WRITELN;
  ix := VSELECT(mk, iv, VSPLAT(-1, V8I));
  FOR i := 0 TO 7 DO WRITE(ix[i], ' ');
  WRITELN;

  FOR i := 0 TO 3 DO e[i] := i * 1.0;   { 0 1 2 3 }
  f := VSPLAT(2.0, V4D);
  m := e >= f;                          { F F T T }
  FOR i := 0 TO 3 DO
    IF m[i] THEN WRITE('T ') ELSE WRITE('F ');
  WRITELN;
  d := VSELECT(m, e, f);                { 2 2 2 3 }
  FOR i := 0 TO 3 DO WRITE(d[i]:0:2, ' ');
  WRITELN
END.
