{ Native Pascal compiler driver. Command-line parsing is kept here so that
  process control and option policy do not move into the C runtime. }
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_driver(input, output);

USES argparse, jsonutil;

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
  inputs, extra_clang_args, extra_objects: RawArgArray;
  input_count, extra_clang_argc, extra_object_count, i: CINT;
  ii, opt_num: INTEGER32;
  output_file, dialect: ADRMEM;
  root_dir, lexer_bin, parser_bin, typechecker_bin, codegen_bin: ADRMEM;
  runtime_lib, cc_bin, opt_level, temp_ll, extra_ll, primary_ll, primary_output: ADRMEM;
  primary_compile_only: BOOLEAN;
  emit_ptx, device_triple, ptx_cpu, device_backend, noalias_params: ADRMEM;
  target_cpu, target_features: ADRMEM;
  in_fd, out_fd: CINT;
  p1, p2, p3: ARRAY[0..1] OF CINT;
  pid1, pid2, pid3, pid4: CINT;
  status1, status2, status3, status4, clang_status, fail_code: CINT;
  option, opt_str: Str255;
  arg_error: ArgStr;
  compile_only, ir_only, verbose, ptx_only: BOOLEAN;

PROCEDURE Usage;
BEGIN
  WRITELN('Usage: pascal1981 [options] <source.pas> [source.pas ...]');
  WRITELN('  -o <file>               Place output into <file>');
  WRITELN('  -c                      Compile to object file only (.o)');
  WRITELN('  -S                      Compile to LLVM IR (.ll) only');
  WRITELN('  --emit-ptx              Emit PTX assembly (.ptx) for device code');
  WRITELN('  -O0, -O1, -O2, -O3      Optimization level (default: -O1)');
  WRITELN('  --dialect <name>        Language dialect: vintage or extended');
  WRITELN('  --target-cpu <cpu>      Host target CPU (LLVM target-cpu attribute)');
  WRITELN('  --target-features <fs>  Host target features, e.g. +avx2,+fma');
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

PROCEDURE PrintArgError;
VAR
  msg: Str255;
  i, n: INTEGER32;
BEGIN
  ArgError(arg_error);
  n := ORD(arg_error[0]);
  msg[0] := CHR(RETYPE(INTEGER, n));
  i := 1;
  WHILE i <= n DO
  BEGIN
    msg[i] := arg_error[i];
    i := i + 1;
  END;
  EPrint(msg);
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

PROCEDURE ExecStage(stage, stage_name, stage_dialect: ADRMEM;
                    fwd_emit_ptx, fwd_noalias, fwd_device_triple,
                    fwd_ptx_cpu, fwd_device_backend,
                    fwd_target_cpu, fwd_target_features: ADRMEM;
                    source_fd, destination_fd: CINT);
{ Every fwd_* is NIL except on the codegen stage, and even there only when the
  driver was given the matching option. They are passed as ordinary CLI
  arguments -- the driver <-> stage interface is command line only, never the
  environment. fwd_emit_ptx / fwd_noalias are bare flags (any non-NIL value
  means "present"); the rest carry a value. }
VAR
  args: ARRAY[0..23] OF ADRMEM;
  n: INTEGER32;
BEGIN
  dup2(source_fd, 0);
  dup2(destination_fd, 1);
  close(in_fd); close(out_fd);
  ClosePipes;
  args[0] := stage_name;
  n := 1;
  IF stage_dialect <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--dialect'); args[n + 1] := stage_dialect;
    n := n + 2;
  END;
  IF fwd_emit_ptx <> NIL THEN
  BEGIN args[n] := MakeCStr('--emit-ptx'); n := n + 1; END;
  IF fwd_noalias <> NIL THEN
  BEGIN args[n] := MakeCStr('--noalias-kernel-params'); n := n + 1; END;
  IF fwd_device_triple <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--device-triple'); args[n + 1] := fwd_device_triple;
    n := n + 2;
  END;
  IF fwd_ptx_cpu <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--ptx-cpu'); args[n + 1] := fwd_ptx_cpu;
    n := n + 2;
  END;
  IF fwd_device_backend <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--device-backend'); args[n + 1] := fwd_device_backend;
    n := n + 2;
  END;
  IF fwd_target_cpu <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--target-cpu'); args[n + 1] := fwd_target_cpu;
    n := n + 2;
  END;
  IF fwd_target_features <> NIL THEN
  BEGIN
    args[n] := MakeCStr('--target-features'); args[n + 1] := fwd_target_features;
    n := n + 2;
  END;
  args[n] := NIL;
  execvp(stage, ADR args);
  exit(127);
END;

FUNCTION RunPipeline(source_name, ir_name: ADRMEM): CINT;
BEGIN
  in_fd := open(source_name, 0, 0);
  IF in_fd < 0 THEN BEGIN RunPipeline := 1; END
  ELSE
  BEGIN
    out_fd := open(ir_name, 577, 420);
    IF out_fd < 0 THEN BEGIN close(in_fd); RunPipeline := 1; END
    ELSE
    BEGIN
      IF (pipe(ADR p1) <> 0) OR (pipe(ADR p2) <> 0) OR (pipe(ADR p3) <> 0) THEN
        RunPipeline := 1
      ELSE
      BEGIN
        pid1 := fork;
        IF pid1 = 0 THEN ExecStage(lexer_bin, MakeCStr('lexer'), NIL,
                                   NIL, NIL, NIL, NIL, NIL, NIL, NIL,
                                   in_fd, p1[1]);
        pid2 := fork;
        IF pid2 = 0 THEN ExecStage(parser_bin, MakeCStr('parser'), dialect,
                                   NIL, NIL, NIL, NIL, NIL, NIL, NIL,
                                   p1[0], p2[1]);
        pid3 := fork;
        IF pid3 = 0 THEN ExecStage(typechecker_bin, MakeCStr('typechecker'), dialect,
                                   NIL, NIL, NIL, NIL, NIL, NIL, NIL,
                                   p2[0], p3[1]);
        pid4 := fork;
        IF pid4 = 0 THEN ExecStage(codegen_bin, MakeCStr('codegen'), dialect,
                                   emit_ptx, noalias_params, device_triple,
                                   ptx_cpu, device_backend,
                                   target_cpu, target_features, p3[0], out_fd);
        close(in_fd); close(out_fd); ClosePipes;
        waitpid(pid1, ADR status1, 0); waitpid(pid2, ADR status2, 0);
        waitpid(pid3, ADR status3, 0); waitpid(pid4, ADR status4, 0);
        RunPipeline := 0;
        IF (status1 DIV 256) <> 0 THEN RunPipeline := status1 DIV 256
        ELSE IF (status2 DIV 256) <> 0 THEN RunPipeline := status2 DIV 256
        ELSE IF (status3 DIV 256) <> 0 THEN RunPipeline := status3 DIV 256
        ELSE IF (status4 DIV 256) <> 0 THEN RunPipeline := status4 DIV 256;
      END;
    END;
  END;
END;

PROCEDURE ExecClang;
VAR
  args: ARRAY[0..270] OF ADRMEM;
  arg_count, i: CINT;
BEGIN
  args[0] := cc_bin;
  args[1] := opt_level;
  arg_count := 2;
  IF compile_only THEN
  BEGIN
    args[arg_count] := MakeCStr('-c');
    arg_count := arg_count + 1;
  END;
  args[arg_count] := temp_ll;
  arg_count := arg_count + 1;
  IF NOT compile_only THEN
  BEGIN
    { Objects first, archives after. A static archive contributes only those
      members that satisfy symbols already undefined when the linker reaches
      it, so a runtime member referenced *only* from a secondary compiland is
      never pulled in if the archive is listed first -- the reference does not
      exist yet at that point, and by the time it does the archive is behind
      us. That produces "undefined reference to pas_..." for a symbol plainly
      present in libpascalrt.a. }
    FOR i := 0 TO extra_object_count - 1 DO
    BEGIN
      args[arg_count] := extra_objects[i];
      arg_count := arg_count + 1;
    END;
    args[arg_count] := runtime_lib;
    arg_count := arg_count + 1;
    args[arg_count] := MakeCStr('-lcjson');
    arg_count := arg_count + 1;
  END;
  FOR i := 0 TO extra_clang_argc - 1 DO
  BEGIN
    args[arg_count] := extra_clang_args[i];
    arg_count := arg_count + 1;
  END;
  args[arg_count] := MakeCStr('-o');
  args[arg_count + 1] := output_file;
  args[arg_count + 2] := NIL;
  execvp(cc_bin, ADR args);
  exit(127);
END;

BEGIN
  { Option parsing is delegated to the shared argparse unit, the same one the
    parser, typechecker, and codegen stages use. -I/-L/-l are registered as
    pass-through prefixes: argparse collects them verbatim, in order, so the
    driver can forward them to clang without interpreting them. -O0..-O3 arrive
    as the glued short form of the -O integer option. }
  ArgBegin('pascal1981', 'Native Pascal-1981 compiler driver.');
  ArgString('output', 'o', '', 'Place output into <file>');
  ArgFlag('compile-only', 'c', 'Compile to object file only (.o)');
  ArgFlag('ir-only', 'S', 'Compile to LLVM IR (.ll) only');
  ArgFlag('verbose', 'v', 'Print pipeline commands');
  ArgFlag('version', 'V', 'Display version information');
  ArgInt('opt', 'O', 1, 'Optimization level 0..3 (default 1)');
  ArgString('dialect', ARG_NO_SHORT, 'vintage',
            'Language dialect: vintage or extended');
  ArgString('device-triple', ARG_NO_SHORT, '', 'Override the device target triple');
  ArgString('ptx-cpu', ARG_NO_SHORT, '', 'Override the PTX target CPU');
  ArgString('target-cpu', ARG_NO_SHORT, '', 'Host target CPU (LLVM target-cpu attribute)');
  ArgString('target-features', ARG_NO_SHORT, '', 'Host target features, e.g. +avx2,+fma');
  ArgString('device-backend', ARG_NO_SHORT, '', 'Select the device code backend');
  ArgFlag('emit-ptx', ARG_NO_SHORT, 'Emit PTX assembly (.ptx) for device code');
  ArgFlag('noalias-kernel-params', ARG_NO_SHORT,
          'Mark device kernel pointer parameters noalias');
  ArgPassthrough('-I');
  ArgPassthrough('-L');
  ArgPassthrough('-l');

  IF NOT ArgParse THEN
  BEGIN
    IF ArgHelpWanted THEN exit(0);
    PrintArgError;
    exit(1);
  END;
  IF ArgGetFlag('version') THEN
  BEGIN
    Version;
    exit(0);
  END;

  input_count := 0;
  extra_clang_argc := 0;
  compile_only := ArgGetFlag('compile-only');
  ir_only := ArgGetFlag('ir-only');
  { PTX is the codegen stage's final product, not something clang can be
    handed: --emit-ptx therefore stops after codegen exactly as -S does,
    rather than needing -S spelled alongside it. Written without it, the
    driver used to pass the PTX text to clang as if it were LLVM IR, and
    the only report was clang's own "expected top-level entity". }
  ptx_only := ArgGetFlag('emit-ptx');
  IF ptx_only AND compile_only THEN
    Fail('error: --emit-ptx and -c cannot be combined');
  ir_only := ir_only OR ptx_only;
  verbose := ArgGetFlag('verbose');

  IF ArgWasGiven('output') THEN output_file := ArgGetRaw('output')
  ELSE output_file := NIL;

  dialect := ArgGetRaw('dialect');
  option := CStrToStr255(dialect);
  IF (option <> 'vintage') AND (option <> 'extended') THEN
    Fail(Join(Join('error: invalid dialect ''', option),
              '''; expected ''vintage'' or ''extended'''));

  opt_num := ArgGetInt('opt');
  IF (opt_num < 0) OR (opt_num > 3) THEN
    Fail('error: optimization level must be 0, 1, 2, or 3');
  opt_str[0] := CHR(3);
  opt_str[1] := '-';
  opt_str[2] := 'O';
  opt_str[3] := CHR(RETYPE(INTEGER, ORD('0') + opt_num));
  opt_level := MakeCStr(opt_str);

  IF ArgGetFlag('emit-ptx') THEN emit_ptx := MakeCStr('true')
  ELSE emit_ptx := NIL;
  IF ArgGetFlag('noalias-kernel-params') THEN noalias_params := MakeCStr('true')
  ELSE noalias_params := NIL;
  IF ArgWasGiven('device-triple') THEN device_triple := ArgGetRaw('device-triple')
  ELSE device_triple := NIL;
  IF ArgWasGiven('ptx-cpu') THEN ptx_cpu := ArgGetRaw('ptx-cpu')
  ELSE ptx_cpu := NIL;
  IF ArgWasGiven('target-cpu') THEN target_cpu := ArgGetRaw('target-cpu')
  ELSE target_cpu := NIL;
  IF ArgWasGiven('target-features') THEN target_features := ArgGetRaw('target-features')
  ELSE target_features := NIL;
  IF ArgWasGiven('device-backend') THEN device_backend := ArgGetRaw('device-backend')
  ELSE device_backend := NIL;

  ii := 0;
  WHILE ii < ArgPosCount DO
  BEGIN
    IF input_count >= MAX_INPUT_FILES THEN Fail('error: too many input files');
    inputs[input_count] := ArgPosRaw(ii);
    input_count := input_count + 1;
    ii := ii + 1;
  END;

  ii := 0;
  WHILE ii < ArgExtraCount DO
  BEGIN
    IF extra_clang_argc >= MAX_INPUT_FILES THEN Fail('error: too many clang arguments');
    extra_clang_args[extra_clang_argc] := ArgExtraRaw(ii);
    extra_clang_argc := extra_clang_argc + 1;
    ii := ii + 1;
  END;

  IF input_count = 0 THEN
  BEGIN
    EPrint('error: no input file specified');
    Usage;
    exit(1);
  END;
  IF (input_count > 1) AND (compile_only OR ir_only) THEN
    Fail('error: -c, -S and --emit-ptx require exactly one input file');
  IF output_file = NIL THEN
  BEGIN
    IF ptx_only THEN output_file := DefaultOutput(inputs[0], '.ptx')
    ELSE IF ir_only THEN output_file := DefaultOutput(inputs[0], '.ll')
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
  { Device / PTX and host target options are handed to the codegen stage as
    command-line arguments (see ExecStage), never through the environment. }
  IF ir_only THEN
    temp_ll := output_file
  ELSE
  BEGIN
    temp_ll := MakeCStr('/tmp/pascal1981_XXXXXX.ll');
    out_fd := mkstemps(temp_ll, 3);
    IF out_fd < 0 THEN Fail('error: opening output file for IR failed');
    close(out_fd);
  END;
  fail_code := RunPipeline(inputs[0], temp_ll);
  IF fail_code <> 0 THEN
  BEGIN
    IF NOT ir_only THEN unlink(temp_ll);
    exit(fail_code);
  END;
  IF ir_only THEN
  BEGIN
    IF verbose THEN
      IF ptx_only THEN EPrint('[driver] Emitted PTX')
      ELSE EPrint('[driver] Emitted IR');
  END
  ELSE
  BEGIN
    primary_ll := temp_ll;
    primary_output := output_file;
    primary_compile_only := compile_only;
    extra_object_count := 0;
    FOR i := 1 TO input_count - 1 DO
    BEGIN
      extra_ll := MakeCStr('/tmp/pascal1981_XXXXXX.ll');
      out_fd := mkstemps(extra_ll, 3);
      IF out_fd < 0 THEN Fail('error: creating temporary IR file failed');
      close(out_fd);
      fail_code := RunPipeline(inputs[i], extra_ll);
      IF fail_code <> 0 THEN BEGIN unlink(extra_ll); exit(fail_code); END;
      extra_objects[extra_object_count] := MakeCStr('/tmp/pascal1981_XXXXXX.o');
      out_fd := mkstemps(extra_objects[extra_object_count], 2);
      IF out_fd < 0 THEN Fail('error: creating temporary object file failed');
      close(out_fd);
      temp_ll := extra_ll;
      output_file := extra_objects[extra_object_count];
      compile_only := TRUE;
      runtime_lib := NIL;
      cc_bin := getenv(MakeCStr('PASCAL1981_CC'));
      IF cc_bin = NIL THEN cc_bin := getenv(MakeCStr('CC'));
      IF cc_bin = NIL THEN cc_bin := MakeCStr('clang');
      pid1 := fork;
      IF pid1 = 0 THEN ExecClang;
      waitpid(pid1, ADR clang_status, 0);
      unlink(extra_ll);
      IF (clang_status DIV 256) <> 0 THEN exit(clang_status DIV 256);
      extra_object_count := extra_object_count + 1;
    END;
    temp_ll := primary_ll;
    output_file := primary_output;
    compile_only := primary_compile_only;
    runtime_lib := getenv(MakeCStr('PASCAL1981_RUNTIME_LIB'));
    IF runtime_lib = NIL THEN runtime_lib := MakeCStr(Join(CStrToStr255(root_dir), '/runtime/build/libpascalrt.a'));
    cc_bin := getenv(MakeCStr('PASCAL1981_CC'));
    IF cc_bin = NIL THEN cc_bin := getenv(MakeCStr('CC'));
    IF cc_bin = NIL THEN cc_bin := MakeCStr('clang');
    pid1 := fork;
    IF pid1 = 0 THEN ExecClang;
    waitpid(pid1, ADR clang_status, 0);
    unlink(temp_ll);
    FOR i := 0 TO extra_object_count - 1 DO unlink(extra_objects[i]);
    IF (clang_status DIV 256) <> 0 THEN exit(clang_status DIV 256);
  END;
END.
