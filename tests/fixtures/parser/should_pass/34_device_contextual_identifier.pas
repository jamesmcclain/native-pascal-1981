{ 'device' is a contextual keyword; it must still be usable as an identifier
  in vintage/host code.  This program uses 'device' as a variable name.       }
PROGRAM test_device_ident;
VAR
  device: INTEGER;
  device_count: INTEGER;
BEGIN
  device := 42;
  device_count := device + 1;
  WRITELN(device_count)
END.
