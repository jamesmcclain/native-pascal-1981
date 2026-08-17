PROGRAM FileIoBasic(output);
VAR
  f: TEXT;
  line: LSTRING(80);
BEGIN
  ASSIGN(f, '/tmp/native_pascal_test_file_io_basic.txt');
  REWRITE(f);
  WRITELN(f, 'hello file');
  WRITELN(f, 42);
  CLOSE(f);

  RESET(f);
  WHILE NOT EOF(f) DO
  BEGIN
    READLN(f, line);
    WRITELN(line);
  END;
  CLOSE(f);
END.
