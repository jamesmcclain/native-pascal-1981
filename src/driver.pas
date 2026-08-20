{ Native Pascal compiler driver. Command-line parsing is kept here so that
  process control and option policy do not move into the C runtime. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_driver(input, output);

USES jsonutil;

FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

CONST
  MAX_INPUT_FILES = 256;

TYPE
  RawArgArray = ARRAY[0..255] OF ADRMEM;

VAR
  inputs: RawArgArray;
  input_count, i: CINT;
  current, output_file: ADRMEM;
  option: Str255;
  compile_only, ir_only, verbose: BOOLEAN;

PROCEDURE Usage;
BEGIN
  WRITELN('Usage: pascal1981 [options] <source.pas> [source.pas ...]');
  WRITELN('  -o <file>               Place output into <file>');
  WRITELN('  -c                      Compile to object file only (.o)');
  WRITELN('  -S                      Compile to LLVM IR (.ll) only');
  WRITELN('  -O0, -O1, -O2, -O3      Optimization level (default: -O1)');
  WRITELN('  -I <dir>                Add directory to include search path');
  WRITELN('  -L <dir>                Add directory to library search path');
  WRITELN('  -l <lib>                Link with library');
  WRITELN('  -v, --verbose           Print pipeline commands');
  WRITELN('  -h, --help              Display this help message');
  WRITELN('  -V, --version           Display version information');
END;

PROCEDURE Fail(message: Str255);
BEGIN
  EPrint(message);
  exit(1);
END;

PROCEDURE Version;
BEGIN
  WRITELN('pascal1981-native (Native Pascal Compiler Driver) 0.1.0');
END;

BEGIN
  input_count := 0;
  output_file := NIL;
  compile_only := FALSE;
  ir_only := FALSE;
  verbose := FALSE;
  i := 1;
  WHILE i < pas_arg_count DO
  BEGIN
    current := pas_arg_value(i);
    option := CStrToStr255(current);
    IF option = '-o' THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: -o requires an argument');
      output_file := pas_arg_value(i);
    END
    ELSE IF option = '-c' THEN
      compile_only := TRUE
    ELSE IF option = '-S' THEN
      ir_only := TRUE
    ELSE IF (option = '-v') OR (option = '--verbose') THEN
      verbose := TRUE
    ELSE IF (option = '-h') OR (option = '--help') THEN
    BEGIN
      Usage;
      exit(0);
    END
    ELSE IF (option = '-V') OR (option = '--version') THEN
    BEGIN
      Version;
      exit(0);
    END
    ELSE IF (option = '--dialect') OR (option = '--device-triple') OR
            (option = '--ptx-cpu') OR (option = '--device-backend') THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: option requires an argument');
    END
    ELSE IF (option = '--emit-ptx') OR (option = '-O0') OR (option = '-O1') OR
            (option = '-O2') OR (option = '-O3') OR (option[1] = '-') THEN
    BEGIN
      IF (option[1] = '-') AND (option <> '-I') AND (option <> '-L') AND
         (option <> '-l') AND (option[2] <> 'O') THEN
        Fail('error: unrecognized command line option');
    END
    ELSE
    BEGIN
      IF input_count >= MAX_INPUT_FILES THEN Fail('error: too many input files');
      inputs[input_count] := current;
      input_count := input_count + 1;
    END;
    i := i + 1;
  END;
  IF input_count = 0 THEN
  BEGIN
    EPrint('error: no input file specified');
    Usage;
    exit(1);
  END;
  IF (input_count > 1) AND (compile_only OR ir_only) THEN
    Fail('error: -c and -S require exactly one input file');
  { Pipeline execution is added after the parsing contract is complete. }
  IF verbose THEN EPrint('[driver] parsed command line');
END.
