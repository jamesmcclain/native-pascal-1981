(*$INCLUDE:'argparse.inc'*)
PROGRAM argparse_help(input, output);
{ --help prints the generated usage text and makes ArgParse return FALSE, with
  ArgHelpWanted telling the caller this was a request rather than a mistake,
  so the caller can exit 0 instead of 2. }
USES argparse;

VAR
  s: ArgStr;

BEGIN
  ArgBegin('argparse_help', 'Fixture for generated help output.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1', 'Host to listen on.');
  ArgInt('port', 'p', 8790, 'Port to listen on.');
  ArgReal('temperature', 't', 0.2, 'Sampling temperature.');
  ArgFlag('verbose', 'v', 'Print more.');

  IF ArgParse THEN
    WRITELN('unexpectedly parsed')
  ELSE
  BEGIN
    WRITELN('help-wanted=', ArgHelpWanted);
    ArgError(s);
    WRITELN('error-empty=', ORD(s[0]) = 0);
  END;
END.
