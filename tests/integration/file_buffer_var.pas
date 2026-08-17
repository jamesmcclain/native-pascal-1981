PROGRAM FileBufferVar(output);
VAR
  f: TEXT;
  c: CHAR;
BEGIN
  ASSIGN(f, '/tmp/native_pascal_test_file_buffer_var.txt');
  REWRITE(f);
  WRITELN(f, 'ab');
  CLOSE(f);

  RESET(f);
  WHILE NOT EOF(f) DO
  BEGIN
    WHILE NOT EOLN(f) DO
    BEGIN
      c := f^;
      WRITE(c);
      GET(f);
    END;
    WRITELN;
    IF NOT EOF(f) THEN READLN(f);
  END;
  CLOSE(f);
END.
