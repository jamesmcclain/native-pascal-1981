PROGRAM for_char_boolean(OUTPUT);
TYPE Small = 'a'..'z';
VAR c: CHAR; f: BOOLEAN; r: Small; n: INTEGER;
BEGIN
  FOR c := 'a' TO 'e' DO WRITE(c); WRITELN;
  FOR c := 'e' DOWNTO 'a' DO WRITE(c); WRITELN;
  FOR f := FALSE TO TRUE DO WRITE(f, ' '); WRITELN;
  FOR f := TRUE DOWNTO FALSE DO WRITE(f, ' '); WRITELN;
  FOR f := TRUE TO FALSE DO WRITE('never'); 
  FOR r := 'x' TO 'z' DO WRITE(r); WRITELN;
  n := 0; FOR c := CHR(250) TO CHR(255) DO n := n + 1; WRITELN(n);
  n := 0; FOR c := CHR(5) DOWNTO CHR(0) DO n := n + 1; WRITELN(n);
  n := 0; FOR c := CHR(127) TO CHR(129) DO n := n + 1; WRITELN(n);
  n := 0; FOR c := 'a' TO 'z' DO BEGIN IF c = 'c' THEN CYCLE; IF c = 'f' THEN BREAK; n := n + 1 END; WRITELN(n);
END.
