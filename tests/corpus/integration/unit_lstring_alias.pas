(*$INCLUDE:'unit_lstring_alias.inc'*)
PROGRAM UnitLStringAlias(output);
USES aliasstate;
VAR
  name: Name;
BEGIN
  name := 'unit alias';
  SetName(name);
  name := '';
  GetName(name);
  WRITELN(name);
END.
