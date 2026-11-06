{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-26: READLN, CONCAT, sets, REAL, a WITH over a captured RECORD, ADR, a
  subrange CASE selector, a CONST LSTRING and a value ARRAY formal, and a
  TEXT file local, all reached from nested routines. }
PROGRAM uplevel_io(INPUT, OUTPUT);
TYPE
  Letters = SET OF CHAR;
  Rec = RECORD n: INTEGER; t: LSTRING(10); END;
  Vec = ARRAY [1..3] OF INTEGER;
  Small = 1..10;

PROCEDURE Work(CONST cs: LSTRING; sv: Vec);
VAR
  line: LSTRING(40);
  total: INTEGER;
  rr: REAL;
  st: Letters;
  rec: Rec;
  a: ADRMEM;
  sm: Small;
  f: TEXT;

  PROCEDURE ReadIt;
  BEGIN
    READLN(line);
    READLN(total);
  END;

  PROCEDURE Grow;
  VAR k: INTEGER;
  BEGIN
    CONCAT(line, '!');
    rr := rr * 2.5;
    st := st + ['q'];
    WITH rec DO
    BEGIN
      n := n + ORD(line.LEN);
      CONCAT(t, cs);
    END;
    a := ADR total;
    FOR k := 1 TO 3 DO total := total + sv[k];
    sm := sm + 1;
    CASE sm OF
      4: WRITELN('four');
      OTHERWISE WRITELN('not four');
    END;
  END;

  PROCEDURE UseFile;
  BEGIN
    ASSIGN(f, 'uplevel_io.tmp');
    REWRITE(f);
    WRITELN(f, 'file line ', total);
    CLOSE(f);
    RESET(f);
    READLN(f, line);
    CLOSE(f);
  END;

BEGIN
  rr := 1.0;
  st := ['a'];
  rec.n := 0;
  rec.t := 'r:';
  sm := 3;
  ReadIt;
  Grow;
  WRITELN(line, ' ', total, ' ', rr:5:2, ' ', 'q' IN st, ' ', rec.n, ' ', rec.t,
          ' ', sm);
  WRITELN(a = ADR total);
  UseFile;
  WRITELN(line);
END;

VAR
  v: Vec;
BEGIN
  v[1] := 1; v[2] := 2; v[3] := 3;
  Work('cs', v);
END.
