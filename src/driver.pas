{ Native Pascal compiler driver. Command-line parsing is kept here so that
  process control and option policy do not move into the C runtime. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_driver(input, output);

USES jsonutil;

FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
FUNCTION getenv(name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION pas_toolchain_root: ADRMEM [C]; EXTERN;
FUNCTION open(path: ADRMEM; flags: CINT; mode: CINT): CINT [C]; EXTERN;
FUNCTION close(fd: CINT): CINT [C]; EXTERN;
FUNCTION pipe(fds: ADRMEM): CINT [C]; EXTERN;
FUNCTION fork: CINT [C]; EXTERN;
FUNCTION dup2(old_fd: CINT; new_fd: CINT): CINT [C]; EXTERN;
FUNCTION waitpid(pid: CINT; status: ADRMEM; options: CINT): CINT [C]; EXTERN;
FUNCTION execvp(file_name: ADRMEM; args: ADRMEM): CINT [C]; EXTERN;
FUNCTION mkstemps(template_name: ADRMEM; suffix_length: CINT): CINT [C]; EXTERN;
FUNCTION unlink(path: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

CONST
  MAX_INPUT_FILES = 256;

TYPE
  RawArgArray = ARRAY[0..255] OF ADRMEM;

VAR
  inputs: RawArgArray;
  input_count, i: CINT;
  current, output_file: ADRMEM;
  root_dir, lexer_bin, parser_bin, typechecker_bin, codegen_bin: ADRMEM;
  runtime_lib, cc_bin, opt_level, temp_ll: ADRMEM;
  in_fd, out_fd: CINT;
  p1, p2, p3: ARRAY[0..1] OF CINT;
  pid1, pid2, pid3, pid4: CINT;
  status1, status2, status3, status4, clang_status, fail_code: CINT;
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

FUNCTION DefaultOutput(input_name: ADRMEM; suffix: Str255): ADRMEM;
VAR
  base: Str255;
  length: INTEGER;
BEGIN
  base := CStrToStr255(input_name);
  length := ORD(base[0]);
  IF (length >= 4) AND (base[length - 3] = '.') AND (base[length - 2] = 'p') AND
     (base[length - 1] = 'a') AND (base[length] = 's') THEN
    base[0] := CHR(length - 4);
  DefaultOutput := MakeCStr(Join(base, suffix));
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

PROCEDURE ExecClang;
VAR
  args: ARRAY[0..7] OF ADRMEM;
BEGIN
  args[0] := cc_bin;
  args[1] := opt_level;
  IF compile_only THEN
  BEGIN
    args[2] := MakeCStr('-c');
    args[3] := temp_ll;
    args[4] := MakeCStr('-o');
    args[5] := output_file;
    args[6] := NIL;
  END
  ELSE
  BEGIN
    args[2] := temp_ll;
    args[3] := runtime_lib;
    args[4] := MakeCStr('-lcjson');
    args[5] := MakeCStr('-o');
    args[6] := output_file;
    args[7] := NIL;
  END;
  execvp(cc_bin, ADR args);
  exit(127);
END;

BEGIN
  input_count := 0;
  output_file := NIL;
  compile_only := FALSE;
  ir_only := FALSE;
  verbose := FALSE;
  opt_level := MakeCStr('-O1');
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
    ELSE IF (option = '-O0') OR (option = '-O1') OR (option = '-O2') OR
            (option = '-O3') THEN
      opt_level := current
    ELSE IF (option = '--emit-ptx') OR (option = '-I') OR (option = '-L') OR
            (option = '-l') THEN
    BEGIN
    END
    ELSE IF option[1] = '-' THEN
      Fail(Join('error: unrecognized command line option: ', option))
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
  IF output_file = NIL THEN
  BEGIN
    IF ir_only THEN output_file := DefaultOutput(inputs[0], '.ll')
    ELSE IF compile_only THEN output_file := DefaultOutput(inputs[0], '.o')
    ELSE output_file := DefaultOutput(inputs[0], '');
  END;
  root_dir := pas_toolchain_root;
  lexer_bin := getenv(MakeCStr('PASCAL1981_LEXER'));
  parser_bin := getenv(MakeCStr('PASCAL1981_PARSER'));
  typechecker_bin := getenv(MakeCStr('PASCAL1981_TYPECHECKER'));
  codegen_bin := getenv(MakeCStr('PASCAL1981_CODEGEN'));
  IF lexer_bin = NIL THEN lexer_bin := MakeCStr(Join(CStrToStr255(root_dir), '/bin/lexer'));
  IF parser_bin = NIL THEN parser_bin := MakeCStr(Join(CStrToStr255(root_dir), '/bin/parser'));
  IF typechecker_bin = NIL THEN typechecker_bin := MakeCStr(Join(CStrToStr255(root_dir), '/bin/typechecker'));
  IF codegen_bin = NIL THEN codegen_bin := MakeCStr(Join(CStrToStr255(root_dir), '/bin/codegen'));
  in_fd := open(inputs[0], 0, 0);
  IF in_fd < 0 THEN Fail('error: opening input file failed');
  IF ir_only THEN
    out_fd := open(output_file, 577, 420)
  ELSE
  BEGIN
    temp_ll := MakeCStr('/tmp/pascal1981_XXXXXX.ll');
    out_fd := mkstemps(temp_ll, 3);
  END;
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
  IF fail_code <> 0 THEN
  BEGIN
    IF NOT ir_only THEN unlink(temp_ll);
    exit(fail_code);
  END;
  IF ir_only THEN
  BEGIN
    IF verbose THEN EPrint('[driver] Emitted IR');
  END
  ELSE
  BEGIN
    runtime_lib := getenv(MakeCStr('PASCAL1981_RUNTIME_LIB'));
    IF runtime_lib = NIL THEN runtime_lib := MakeCStr(Join(CStrToStr255(root_dir), '/runtime/build/libpascalrt.a'));
    cc_bin := getenv(MakeCStr('PASCAL1981_CC'));
    IF cc_bin = NIL THEN cc_bin := getenv(MakeCStr('CC'));
    IF cc_bin = NIL THEN cc_bin := MakeCStr('clang');
    pid1 := fork;
    IF pid1 = 0 THEN ExecClang;
    waitpid(pid1, ADR clang_status, 0);
    unlink(temp_ll);
    IF (clang_status DIV 256) <> 0 THEN exit(clang_status DIV 256);
  END;
END.
