PROGRAM VintageEnumIo(input, output);
TYPE
  Color = (RED, GREEN, BLUE);
VAR
  color_value: Color;
  truth, falsehood: BOOLEAN;
  data_file: TEXT;
BEGIN
  WRITELN(GREEN);
  WRITELN(TRUE);
  WRITELN(FALSE);

  READLN(color_value);
  READLN(truth);
  READLN(falsehood);
  WRITELN(color_value);
  WRITELN(truth);
  WRITELN(falsehood);

  ASSIGN(data_file, '/tmp/native_pascal_vintage_enum_io.txt');
  REWRITE(data_file);
  WRITELN(data_file, BLUE);
  WRITELN(data_file, FALSE);
  CLOSE(data_file);
  RESET(data_file);
  READLN(data_file, color_value);
  READLN(data_file, falsehood);
  CLOSE(data_file);
  WRITELN(color_value);
  WRITELN(falsehood)
END.
