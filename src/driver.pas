{ Native Pascal compiler driver. Command-line parsing is kept here so that
  process control and option policy do not move into the C runtime. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_driver(input, output);

USES jsonutil;

FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
FUNCTION getenv(name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION open(path: ADRMEM; flags: CINT; mode: CINT): CINT [C]; EXTERN;
FUNCTION close(fd: CINT): CINT [C]; EXTERN;
FUNCTION pipe(fds: ADRMEM): CINT [C]; EXTERN;
FUNCTION fork: CINT [C]; EXTERN;
FUNCTION dup2(old_fd: CINT; new_fd: CINT): CINT [C]; EXTERN;
FUNCTION waitpid(pid: CINT; status: ADRMEM; options: CINT): CINT [C]; EXTERN;
FUNCTION execvp(file_name: ADRMEM; args: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

CONST
  MAX_INPUT_FILES = 256;

TYPE
  RawArgArray = ARRAY[0..255] OF ADRMEM;

VAR
  inputs: RawArgArray;
  input_count, i: CINT;
  current, output_file: ADRMEM;
  lexer_bin, parser_bin, typechecker_bin, codegen_bin: ADRMEM;
  in_fd, out_fd: CINT;
  p1, p2, p3: ARRAY[0..1] OF CINT;
  pid1, pid2, pid3, pid4: CINT;
  status1, status2, status3, status4, fail_code: CINT;
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

FUNCTION Join(prefix, suffix: Str255): Str255;
VAR
  result: Str255;
  i, prefix_length, suffix_length: INTEGER;
BEGIN
  prefix_length := ORD(prefix[0]);
  suffix_length := ORD(suffix[0]);
  IF prefix_length + suffix_length > 255 THEN
    suffix_length := 255 - prefix_length;
  result[0] := CHR(prefix_length + suffix_length);
  FOR i := 1 TO prefix_length DO result[i] := prefix[i];
  FOR i := 1 TO suffix_length DO result[prefix_length + i] := suffix[i];
  Join := result;
END;

PROCEDURE Version;
BEGIN
  WRITELN('pascal1981-native (Native Pascal Compiler Driver) 0.1.0');
END;

PROCEDURE ClosePipes;
BEGIN
  close(p1[0]); close(p1[1]);
  close(p2[0]); close(p2[1]);
  close(p3[0]); close(p3[1]);
END;

PROCEDURE ExecStage(stage, stage_name: ADRMEM; source_fd, destination_fd: CINT);
VAR
  args: ARRAY[0..1] OF ADRMEM;
BEGIN
  dup2(source_fd, 0);
  dup2(destination_fd, 1);
  close(in_fd); close(out_fd);
  ClosePipes;
  args[0] := stage_name;
  args[1] := NIL;
  execvp(stage, ADR args);
  exit(127);
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
    ELSE IF option = '--dialect' THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: --dialect requires an argument');
    END
    ELSE IF option = '--device-triple' THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: --device-triple requires an argument');
    END
    ELSE IF option = '--ptx-cpu' THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: --ptx-cpu requires an argument');
    END
    ELSE IF option = '--device-backend' THEN
    BEGIN
      i := i + 1;
      IF i >= pas_arg_count THEN Fail('error: --device-backend requires an argument');
    END
    ELSE IF (option = '--emit-ptx') OR (option = '-O0') OR (option = '-O1') OR
            (option = '-O2') OR (option = '-O3') OR (option[1] = '-') THEN
    BEGIN
      IF (option[1] = '-') AND (option <> '-I') AND (option <> '-L') AND
         (option <> '-l') AND (option[2] <> 'O') THEN
        Fail(Join('error: unrecognized command line option: ', option));
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
  IF NOT ir_only THEN
    Fail('error: driver pipeline is not complete');
  IF output_file = NIL THEN
    Fail('error: output file is required until default output names are implemented');
  lexer_bin := getenv(MakeCStr('PASCAL1981_LEXER'));
  parser_bin := getenv(MakeCStr('PASCAL1981_PARSER'));
  typechecker_bin := getenv(MakeCStr('PASCAL1981_TYPECHECKER'));
  codegen_bin := getenv(MakeCStr('PASCAL1981_CODEGEN'));
  IF (lexer_bin = NIL) OR (parser_bin = NIL) OR (typechecker_bin = NIL) OR
     (codegen_bin = NIL) THEN
    Fail('error: compiler stage binaries not found in bin/. Please run make bootstrap first.');
  in_fd := open(inputs[0], 0, 0);
  IF in_fd < 0 THEN Fail('error: opening input file failed');
  out_fd := open(output_file, 577, 420);
  IF out_fd < 0 THEN Fail('error: opening output file for IR failed');
  IF (pipe(ADR p1) <> 0) OR (pipe(ADR p2) <> 0) OR (pipe(ADR p3) <> 0) THEN
    Fail('error: pipe creation failed');
  pid1 := fork;
  IF pid1 = 0 THEN ExecStage(lexer_bin, MakeCStr('lexer'), in_fd, p1[1]);
  pid2 := fork;
  IF pid2 = 0 THEN ExecStage(parser_bin, MakeCStr('parser'), p1[0], p2[1]);
  pid3 := fork;
  IF pid3 = 0 THEN ExecStage(typechecker_bin, MakeCStr('typechecker'), p2[0], p3[1]);
  pid4 := fork;
  IF pid4 = 0 THEN ExecStage(codegen_bin, MakeCStr('codegen'), p3[0], out_fd);
  close(in_fd); close(out_fd); ClosePipes;
  waitpid(pid1, ADR status1, 0);
  waitpid(pid2, ADR status2, 0);
  waitpid(pid3, ADR status3, 0);
  waitpid(pid4, ADR status4, 0);
  fail_code := 0;
  IF (status1 DIV 256) <> 0 THEN fail_code := status1 DIV 256
  ELSE IF (status2 DIV 256) <> 0 THEN fail_code := status2 DIV 256
  ELSE IF (status3 DIV 256) <> 0 THEN fail_code := status3 DIV 256
  ELSE IF (status4 DIV 256) <> 0 THEN fail_code := status4 DIV 256;
  IF fail_code <> 0 THEN exit(fail_code);
  IF verbose THEN EPrint('[driver] Emitted IR');
END.
