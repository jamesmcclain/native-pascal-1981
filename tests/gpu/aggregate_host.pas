(*$INCLUDE:'aggregate.inc'*)
PROGRAM aggregate_host(output);
USES aggregateu (probe, entry8, entry12, entry16, entry20);
VAR
  host_out: ARRAY [0..11] OF INTEGER32;
  device_out: ADRMEM;
  a8: T8;
  a12: T12;
  a16: T16;
  a20: T20;
  i: INTEGER;
BEGIN
  FOR i := 0 TO 11 DO host_out[i] := 0;
  a8.a := 1; a8.b := 2;
  a12.a := 1; a12.b := 2; a12.c := 3;
  a16.a := 1; a16.b := 2; a16.c := 3; a16.d := 4;
  a20.a := 1; a20.b := 2; a20.c := 3; a20.d := 4; a20.e := 5;
  device_out := DEVALLOC(48);
  LAUNCH(probe, 1, 1, device_out);
  LAUNCH(entry8, 1, 1, device_out, a8);
  LAUNCH(entry12, 1, 1, device_out, a12);
  LAUNCH(entry16, 1, 1, device_out, a16);
  LAUNCH(entry20, 1, 1, device_out, a20);
  DEVCOPYFROM(ADR host_out, device_out, 48);
  FOR i := 0 TO 11 DO WRITELN(host_out[i]);
  DEVFREE(device_out)
END.
