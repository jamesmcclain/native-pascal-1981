PROGRAM partial(n, tag);
{ One heading parameter supplied on the command line, the next absent: the
  first binds silently from argv[1], the second prompts at the keyboard and
  reads from stdin (manual 13-5..13-7). The .stdin file stands in for the
  keyboard. }
VAR
  n: INTEGER;
  tag: LSTRING(32);
BEGIN
  WRITELN('n=', n);
  WRITELN('tag=', tag);
END.
