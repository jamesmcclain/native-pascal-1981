(*$INCLUDE:'unit_lstring_alias.inc'*)
PROGRAM UnitLStringAlias(output);
USES aliasstate;
VAR
  cur_name: Name;
BEGIN
  cur_name := 'unit alias';
  SetName(cur_name);
  cur_name := '';
  GetName(cur_name);
  WRITELN(cur_name);
END.
