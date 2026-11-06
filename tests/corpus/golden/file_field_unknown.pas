{ DIALECT: vintage extended }
PROGRAM FileFieldUnknown(OUTPUT);
{ F.TRAP and F.ERRS are a file's only selectable fields; F.MODE needs
  the FILEMODES type, which is not predeclared. }
VAR f: TEXT;
BEGIN
  f.TRAP := TRUE;
  WRITELN(f.Status);
  f.MODE := f.MODE
END.
