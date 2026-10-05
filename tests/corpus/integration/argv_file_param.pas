PROGRAM readf(infile, output);
{ A FILE-typed heading parameter takes its filename from the command line;
  the token is ASSIGNed to the file's FCB so the later RESET opens exactly
  that file (manual 13-5..13-7). The data file is argv_file_param.data,
  named in argv_file_param.args relative to the repository root. }
VAR
  infile: TEXT;
  line: LSTRING(80);
BEGIN
  RESET(infile);
  WHILE NOT EOF(infile) DO
  BEGIN
    READLN(infile, line);
    WRITELN('got: ', line);
  END;
  CLOSE(infile);
END.
