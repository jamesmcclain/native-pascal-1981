{ NEW-48: CONST formals are read-only (assignment, component writes, WITH,
  VAR actuals, and mutating builtins are all rejected in the typechecker). }
PROGRAM const_param_readonly;
TYPE
  S4 = STRING(4);
  L4 = LSTRING(4);
  Rec = RECORD
    x: INTEGER;
  END;
  IntPtr = ^INTEGER;
  CharSet = SET OF CHAR;

PROCEDURE TakeVar(VAR v: INTEGER);
BEGIN
  v := 0;
END;

PROCEDURE TakeVarStr(VAR v: STRING);
BEGIN
END;

PROCEDURE Bad(CONST n: INTEGER; CONST s: S4; CONST l: L4;
              CONST r: Rec; CONST p: IntPtr;
              CONST ss: STRING; CONST sl: LSTRING);
VAR
  cs: CharSet;
BEGIN
  cs := ['a'];
  n := 5;
  s[1] := 'z';
  l[1] := 'z';
  l.len := CHR(1);
  r.x := 1;
  WITH r DO
    x := 2;
  p := NIL;
  ss[1] := 'z';
  sl[1] := 'z';
  TakeVar(n);
  TakeVar(r.x);
  TakeVarStr(s);
  COPYSTR('ab', s);
  COPYLST('ab', l);
  INSERT('a', l, 1);
  DELETE(l, 1, 1);
  CONCAT(l, 'a');
  NEW(p);
  DISPOSE(p);
  READ(n);
  READSET(l, cs);
END;

BEGIN
END.
