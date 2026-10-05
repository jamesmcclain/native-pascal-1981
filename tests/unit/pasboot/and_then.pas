{ AND and OR evaluate both operands; AND THEN short-circuits. }
(*$INCLUDE:'testio.inc'*)
PROGRAM and_then(input, output);
USES testio;

VAR
  b: BOOLEAN;

FUNCTION Noisy(v: BOOLEAN): BOOLEAN;
BEGIN
  call_count := call_count + 1;
  Noisy := v;
END;

BEGIN
  call_count := 0;
  b := Noisy(FALSE) AND Noisy(TRUE);
  WriteLabel('FALSE AND x');
  WriteBool(b);
  WRITELN;
  ReportCalls;
  call_count := 0;
  b := Noisy(TRUE) OR Noisy(FALSE);
  WriteLabel('TRUE OR x');
  WriteBool(b);
  WRITELN;
  ReportCalls;
  call_count := 0;
  b := TRUE;
  IF Noisy(FALSE) AND THEN Noisy(TRUE) THEN
    b := TRUE
  ELSE
    b := FALSE;
  WriteLabel('FALSE AND THEN x');
  WriteBool(b);
  WRITELN;
  ReportCalls;
  call_count := 0;
  b := FALSE;
  WHILE Noisy(TRUE) AND THEN Noisy(NOT b) DO
    b := TRUE;
  WriteLabel('TRUE AND THEN x');
  WriteBool(b);
  WRITELN;
  ReportCalls;
  WriteLabel('NOT');
  WriteBool(NOT b);
  WRITELN;
END.
