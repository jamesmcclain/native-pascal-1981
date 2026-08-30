(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
PROGRAM argparse_unit(input, output);
{ Exercises argparse over the option set the completion proxy actually needs,
  through every accepted spelling in one command line: --long value,
  --long=value, a short flag, a value long enough that an LSTRING could not
  hold it, and "--" ending the options so that a following token that looks
  like an option is treated as positional.

  Note the program heading names only INPUT and OUTPUT. Naming any further
  program parameter would bind argv positionally during startup and defeat the
  whole exercise -- see the warning in argparse.inc. }
USES bytebuf, argparse;

VAR
  s: ArgStr;
  raw_len: ByteBuf;
  i: INTEGER32;

BEGIN
  ArgBegin('argparse_unit', 'Fixture for the argparse unit.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1', 'Host to listen on.');
  ArgInt('port', 'p', 8790, 'Port to listen on.');
  ArgString('llm-base-url', ARG_NO_SHORT, 'http://127.0.0.1:8080/v1', 'Backend URL.');
  ArgInt('max-tokens', ARG_NO_SHORT, 512, 'Token budget.');
  ArgReal('temperature', 't', 0.2, 'Sampling temperature.');
  ArgFlag('verbose', 'v', 'Print more.');
  ArgFlag('quiet', 'q', 'Print less.');

  IF NOT ArgParse THEN
  BEGIN
    ArgError(s);
    WRITELN('parse failed: ', s);
  END
  ELSE
  BEGIN
    ArgGetStr('host', s);
    WRITELN('host=', s);
    WRITELN('port=', ArgGetInt('port'));
    WRITELN('max-tokens=', ArgGetInt('max-tokens'));
    WRITELN('temperature=', ArgGetReal('temperature'):0:2);
    WRITELN('verbose=', ArgGetFlag('verbose'));
    WRITELN('quiet=', ArgGetFlag('quiet'));
    WRITELN('quiet-given=', ArgWasGiven('quiet'));
    WRITELN('host-given=', ArgWasGiven('host'));

    { A value longer than 255 characters survives intact through ArgGetRaw,
      while ArgGetStr necessarily truncates. Measuring the raw one through a
      ByteBuf is also a small check that the two units compose. }
    BufInit(raw_len, 0);
    BufAppendCStr(raw_len, ArgGetRaw('llm-base-url'));
    WRITELN('url-raw-len=', BufLen(raw_len));
    ArgGetStr('llm-base-url', s);
    WRITELN('url-str-len=', ORD(s[0]));
    BufFree(raw_len);

    WRITELN('positional=', ArgPosCount);
    i := 0;
    WHILE i < ArgPosCount DO
    BEGIN
      ArgPosStr(i, s);
      WRITELN('  [', i, ']=', s);
      i := i + 1;
    END;
  END;
END.
