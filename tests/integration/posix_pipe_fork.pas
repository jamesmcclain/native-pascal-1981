PROGRAM posix_pipe_fork(input, output);
{ Prove the direct POSIX calls that the Pascal driver will use. }
FUNCTION pipe(fds: ADRMEM): CINT [C]; EXTERN;
FUNCTION fork: CINT [C]; EXTERN;
FUNCTION close(fd: CINT): CINT [C]; EXTERN;
FUNCTION waitpid(pid: CINT; status: ADRMEM; options: CINT): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
VAR
  fds: ARRAY[0..1] OF CINT;
  status, pid: CINT;
BEGIN
  IF pipe(ADR fds) <> 0 THEN exit(1);
  pid := fork;
  IF pid = 0 THEN
  BEGIN
    close(fds[0]);
    close(fds[1]);
    exit(7);
  END;
  close(fds[0]);
  close(fds[1]);
  waitpid(pid, ADR status, 0);
  WRITELN(status DIV 256);
END.
