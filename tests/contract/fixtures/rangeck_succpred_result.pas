PROGRAM ResultDomain;
TYPE Small = -2..3;
  Top = 0..32767;
VAR seed: INTEGER;
FUNCTION GetValue(x: INTEGER): Small;
BEGIN WRITELN('call'); GetValue := x END;
FUNCTION GetBare: Small;
BEGIN WRITELN('call'); GetBare := seed END;
FUNCTION GetTop: Top;
BEGIN WRITELN('call'); GetTop := 32767 END;
BEGIN
  seed := {SEED};
  WRITELN('prefix');
  WRITELN({EXPR});
  WRITELN('end');
END.
