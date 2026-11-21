{ DIALECT: vintage extended }
{ CMP-24r: bad selectors on a function call with arguments and passing a
  call-result string selector to a VAR STRING formal are rejected by the
  typechecker. }
PROGRAM CallResultSelectBad;
TYPE
  name5 = STRING(5);
  rec = RECORD f: INTEGER; s: name5 END;
FUNCTION mk(v: INTEGER): rec;
BEGIN
  mk.f := v;
  mk.s := 'hello'
END;
PROCEDURE take_var_str(VAR s: STRING);
BEGIN
END;
BEGIN
  WRITELN(mk(1).missing);
  take_var_str(mk(1).s)
END.
