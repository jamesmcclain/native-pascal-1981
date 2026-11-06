{ DIALECT: vintage extended }
PROGRAM FileTrapUntrapped(OUTPUT);
{ With F.TRAP cleared, a malformed READ aborts with its usual message,
  as it does when F.TRAP was never set. }
VAR
  f: TEXT;
  i: INTEGER;
BEGIN
  REWRITE(f);
  WRITELN(f, 'x x');
  RESET(f);
  f.TRAP := TRUE;
  READ(f, i);
  WRITELN('trapped errs=', f.ERRS);
  f.ERRS := 0;
  f.TRAP := FALSE;
  READ(f, i);
  WRITELN('not reached')
END.
