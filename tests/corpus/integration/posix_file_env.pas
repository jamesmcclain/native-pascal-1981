PROGRAM posix_file_env(input, output);
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
FUNCTION open(path: ADRMEM; flags: CINT; mode: CINT): CINT [C]; EXTERN;
FUNCTION close(fd: CINT): CINT [C]; EXTERN;
FUNCTION dup2(old_fd: CINT; new_fd: CINT): CINT [C]; EXTERN;
FUNCTION unlink(path: ADRMEM): CINT [C]; EXTERN;
FUNCTION getenv(name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION setenv(name: ADRMEM; new_value: ADRMEM; replace: CINT): CINT [C]; EXTERN;
TYPE
  STR255 = LSTRING(255);
  CHARBUF = ARRAY[0..255] OF CHAR;
  PCHARBUF = ^CHARBUF;
FUNCTION MakeCStr(s: STR255): ADRMEM;
VAR
  result: ADRMEM;
  text: PCHARBUF;
  i, length: INTEGER;
BEGIN
  result := malloc(256);
  text := result;
  length := ORD(s[0]);
  FOR i := 0 TO length - 1 DO text^[i] := s[i + 1];
  text^[length] := CHR(0);
  MakeCStr := result;
END;
VAR
  fd, result: CINT;
  env_value: ADRMEM;
BEGIN
  result := setenv(MakeCStr('PASCAL1981_POSIX_PROBE'), MakeCStr('present'), 1);
  env_value := getenv(MakeCStr('PASCAL1981_POSIX_PROBE'));
  IF (result <> 0) OR (env_value = NIL) THEN
    result := 1
  ELSE
  BEGIN
    fd := open(MakeCStr('pascal1981_posix_probe.tmp'), 66, 384);
    IF fd < 0 THEN
      result := 2
    ELSE
    BEGIN
      result := dup2(fd, 9);
      close(fd);
      close(9);
      IF result = 9 THEN
        result := unlink(MakeCStr('pascal1981_posix_probe.tmp'))
      ELSE
        result := 3;
    END;
  END;
  WRITELN(result);
END.
