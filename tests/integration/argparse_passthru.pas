{ DIALECT: extended }
(*$INCLUDE:'argparse.inc'*)
PROGRAM argparse_passthru(input, output);
{ Exercises the argparse extensions the compiler driver relies on:

    - a short option glued straight to its value, no space or '=' (-O2);
    - pass-through prefixes that collect clang-style flags verbatim and in
      command-line order, including repeated occurrences (-I, -L, -l);
    - a positional count above the old ARG_MAX_POSITIONAL = 32 limit.

  The program heading names only INPUT and OUTPUT -- see the warning in
  argparse.inc. }
USES argparse;

VAR
  s: ArgStr;
  i: INTEGER32;

BEGIN
  ArgBegin('argparse_passthru',
           'Fixture for argparse pass-through and glued short values.');
  ArgInt('opt', 'O', 1, 'Optimization level.');
  ArgFlag('verbose', 'v', 'Print more.');
  ArgString('output', 'o', 'a.out', 'Output file.');
  ArgPassthrough('-I');
  ArgPassthrough('-L');
  ArgPassthrough('-l');

  IF NOT ArgParse THEN
  BEGIN
    ArgError(s);
    WRITELN('parse failed: ', s);
  END
  ELSE
  BEGIN
    WRITELN('opt=', ArgGetInt('opt'));
    WRITELN('verbose=', ArgGetFlag('verbose'));
    ArgGetStr('output', s);
    WRITELN('output=', s);
    WRITELN('extra=', ArgExtraCount);
    i := 0;
    WHILE i < ArgExtraCount DO
    BEGIN
      ArgExtraStr(i, s);
      WRITELN('  ', s);
      i := i + 1;
    END;
    WRITELN('positional=', ArgPosCount);
  END;
END.
