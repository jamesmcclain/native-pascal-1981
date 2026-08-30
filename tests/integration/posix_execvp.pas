{ DIALECT: extended }
PROGRAM posix_execvp(input, output);
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
FUNCTION fork: CINT [C]; EXTERN;
FUNCTION waitpid(pid: CINT; status: ADRMEM; options: CINT): CINT [C]; EXTERN;
FUNCTION execvp(file_name: ADRMEM; args: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
TYPE
  CHARBUF = ARRAY[0..255] OF CHAR;
  PCHAR = ^CHARBUF;
VAR
  args: ARRAY[0..2] OF ADRMEM;
  pid, status: CINT;
  true_name, true_path: ADRMEM;
  text: PCHAR;
BEGIN
  true_name := malloc(5);
  text := true_name;
  text^[0] := 't'; text^[1] := 'r'; text^[2] := 'u'; text^[3] := 'e'; text^[4] := CHR(0);
  true_path := malloc(10);
  text := true_path;
  text^[0] := '/'; text^[1] := 'b'; text^[2] := 'i'; text^[3] := 'n'; text^[4] := '/'; text^[5] := 't'; text^[6] := 'r'; text^[7] := 'u'; text^[8] := 'e'; text^[9] := CHR(0);
  args[0] := true_name;
  args[1] := NIL;
  pid := fork;
  IF pid = 0 THEN
  BEGIN
    execvp(true_path, ADR args);
    exit(127);
  END;
  waitpid(pid, ADR status, 0);
  WRITELN(status DIV 256);
END.
