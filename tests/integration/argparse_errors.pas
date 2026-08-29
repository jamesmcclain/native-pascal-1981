(*$INCLUDE:'argparse.inc'*)
PROGRAM argparse_errors(input, output);
{ The diagnostic paths. ArgBegin resets all state, so one program can run
  several independent registration/parse cycles against the same argv, which
  is how three distinct failures are covered from a single command line.

  The unit reports failures rather than calling exit() itself, so the caller
  keeps control of the exit status; these cycles simply print what happened. }
USES argparse;

VAR
  s: ArgStr;

BEGIN
  { A duplicate registration is a programming error, surfaced at parse time
    rather than silently dropping the second spelling. }
  ArgBegin('argparse_errors', 'Diagnostics.');
  ArgString('host', ' ', '127.0.0.1', 'Host.');
  ArgString('host', ' ', 'other', 'Host again.');
  IF ArgParse THEN
    WRITELN('1: unexpectedly succeeded')
  ELSE
  BEGIN
    ArgError(s);
    WRITELN('1: ', s);
  END;

  { An option the program never registered. }
  ArgBegin('argparse_errors', 'Diagnostics.');
  ArgString('host', ' ', '127.0.0.1', 'Host.');
  IF ArgParse THEN
    WRITELN('2: unexpectedly succeeded')
  ELSE
  BEGIN
    ArgError(s);
    WRITELN('2: ', s);
  END;

  { A value-taking option given as the final token, with nothing after it. }
  ArgBegin('argparse_errors', 'Diagnostics.');
  ArgString('not-registered', ' ', 'fallback', 'Takes a value.');
  IF ArgParse THEN
    WRITELN('3: unexpectedly succeeded')
  ELSE
  BEGIN
    ArgError(s);
    WRITELN('3: ', s);
  END;

  WRITELN('help-wanted=', ArgHelpWanted);
END.
