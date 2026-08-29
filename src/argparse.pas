{ IMPLEMENTATION of argparse. See argparse.inc for the contract, the accepted
  grammar, and the warning about program-heading parameters. }

(*$INCLUDE:'argparse.inc'*)

IMPLEMENTATION OF argparse;

FUNCTION pas_arg_count: CINT [C]; EXTERN;
FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
FUNCTION strtol(s: ADRMEM; endp: ADRMEM; base: CINT): INTEGER64 [C]; EXTERN;
FUNCTION strtod(s: ADRMEM; endp: ADRMEM): REAL [C]; EXTERN;

CONST
  ARG_KIND_FLAG   = 0;
  ARG_KIND_STRING = 1;
  ARG_KIND_INT    = 2;
  ARG_KIND_REAL   = 3;

TYPE
  ArgSpec = RECORD
    long_name:  ArgStr;
    help:       ArgStr;
    def_str:    ArgStr;
    short_name: CHAR;
    kind:       INTEGER;
    given:      BOOLEAN;
    flag_on:    BOOLEAN;
    value_ptr:  ADRMEM;     { into argv; NIL unless given }
    def_int:    INTEGER32;
    def_real:   REAL;
  END;

VAR
  arg_specs:     ARRAY [0..ARG_MAX_OPTIONS] OF ArgSpec;
  arg_nspecs:    INTEGER32;
  arg_positional: ARRAY [0..ARG_MAX_POSITIONAL] OF ADRMEM;
  arg_npositional: INTEGER32;
  arg_prog:      ArgStr;
  arg_desc:      ArgStr;
  arg_error_msg: ArgStr;
  arg_have_error: BOOLEAN;
  arg_help_wanted: BOOLEAN;

{ ------------------------------------------------------------------ }
{ Small string helpers                                                }
{                                                                     }
{ Local rather than borrowed from jsonutil: argparse is a runtime      }
{ component and should not pull a JSON library in behind it.          }
{ ------------------------------------------------------------------ }

PROCEDURE ArgSetStr(VAR dst: ArgStr; src: ArgStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := ORD(src[0]);
  dst[0] := CHR(RETYPE(INTEGER, n));
  i := 1;
  WHILE i <= n DO
  BEGIN
    dst[i] := src[i];
    i := i + 1;
  END;
END;

PROCEDURE ArgAppendStr(VAR dst: ArgStr; src: ArgStr);
VAR
  i, n, have: INTEGER32;
BEGIN
  have := ORD(dst[0]);
  n := ORD(src[0]);
  i := 1;
  WHILE (i <= n) AND (have < 255) DO
  BEGIN
    have := have + 1;
    dst[have] := src[i];
    i := i + 1;
  END;
  dst[0] := CHR(RETYPE(INTEGER, have));
END;

FUNCTION ArgCStrLen(p: ADRMEM): INTEGER32;
VAR
  base, q: ^CHAR;
  n: INTEGER32;
BEGIN
  n := 0;
  IF p <> NIL THEN
  BEGIN
    base := p;
    q := base + n;
    WHILE q^ <> CHR(0) DO
    BEGIN
      n := n + 1;
      q := base + n;
    END;
  END;
  ArgCStrLen := n;
END;

PROCEDURE ArgCStrToStr(p: ADRMEM; VAR out: ArgStr);
VAR
  base, q: ^CHAR;
  i, n: INTEGER32;
BEGIN
  n := ArgCStrLen(p);
  IF n > 255 THEN n := 255;
  out[0] := CHR(RETYPE(INTEGER, n));
  IF n > 0 THEN
  BEGIN
    base := p;
    i := 0;
    WHILE i < n DO
    BEGIN
      q := base + i;
      out[i + 1] := q^;
      i := i + 1;
    END;
  END;
END;

{ A NUL-terminated copy on the heap. Used only for defaults, at startup, so
  the allocation is bounded by the number of registered options. }
FUNCTION ArgStrToCStr(s: ArgStr): ADRMEM;
VAR
  raw: ADRMEM;
  base, p: ^CHAR;
  i, n: INTEGER32;
BEGIN
  n := ORD(s[0]);
  raw := malloc(n + 1);
  base := raw;
  i := 0;
  WHILE i < n DO
  BEGIN
    p := base + i;
    p^ := s[i + 1];
    i := i + 1;
  END;
  p := base + n;
  p^ := CHR(0);
  ArgStrToCStr := raw;
END;

{ Drop the leading "-" or "--" so the remainder can be matched against the
  registered long name, which is stored without dashes. }
PROCEDURE ArgDropPrefix(VAR s: ArgStr; count: INTEGER32);
VAR
  i, n, drop_count: INTEGER32;
BEGIN
  n := ORD(s[0]);
  IF count > n THEN drop_count := n
  ELSE drop_count := count;
  i := 1;
  WHILE i <= n - drop_count DO
  BEGIN
    s[i] := s[i + drop_count];
    i := i + 1;
  END;
  s[0] := CHR(RETYPE(INTEGER, n - drop_count));
END;

FUNCTION ArgStrEq(a: ArgStr; b: ArgStr): BOOLEAN;
VAR
  i, n: INTEGER32;
  ok: BOOLEAN;
BEGIN
  n := ORD(a[0]);
  IF n <> ORD(b[0]) THEN
    ArgStrEq := FALSE
  ELSE
  BEGIN
    ok := TRUE;
    i := 1;
    WHILE (i <= n) AND ok DO
    BEGIN
      IF a[i] <> b[i] THEN ok := FALSE;
      i := i + 1;
    END;
    ArgStrEq := ok;
  END;
END;

PROCEDURE ArgFail(msg: ArgStr; detail: ArgStr);
BEGIN
  IF NOT arg_have_error THEN
  BEGIN
    arg_have_error := TRUE;
    ArgSetStr(arg_error_msg, msg);
    ArgAppendStr(arg_error_msg, detail);
  END;
END;

{ ------------------------------------------------------------------ }
{ Registration                                                        }
{ ------------------------------------------------------------------ }

FUNCTION ArgFind(long_name: ArgStr): INTEGER32;
VAR
  i, found: INTEGER32;
BEGIN
  found := -1;
  i := 0;
  WHILE (i < arg_nspecs) AND (found < 0) DO
  BEGIN
    IF ArgStrEq(arg_specs[i].long_name, long_name) THEN found := i;
    i := i + 1;
  END;
  ArgFind := found;
END;

PROCEDURE ArgBegin(program_name: ArgStr; description: ArgStr);
BEGIN
  arg_nspecs := 0;
  arg_npositional := 0;
  arg_have_error := FALSE;
  arg_help_wanted := FALSE;
  ArgSetStr(arg_prog, program_name);
  ArgSetStr(arg_desc, description);
  ArgSetStr(arg_error_msg, '');
END;

PROCEDURE ArgAdd(long_name: ArgStr; short_name: CHAR; help: ArgStr;
                 kind: INTEGER);
VAR
  slot: INTEGER32;
BEGIN
  IF arg_nspecs >= ARG_MAX_OPTIONS THEN
    ArgFail('too many registered options: ', long_name)
  ELSE IF ArgFind(long_name) >= 0 THEN
    ArgFail('duplicate option registered: ', long_name)
  ELSE
  BEGIN
    slot := arg_nspecs;
    ArgSetStr(arg_specs[slot].long_name, long_name);
    ArgSetStr(arg_specs[slot].help, help);
    ArgSetStr(arg_specs[slot].def_str, '');
    arg_specs[slot].short_name := short_name;
    arg_specs[slot].kind := kind;
    arg_specs[slot].given := FALSE;
    arg_specs[slot].flag_on := FALSE;
    arg_specs[slot].value_ptr := NIL;
    arg_specs[slot].def_int := 0;
    arg_specs[slot].def_real := 0.0;
    arg_nspecs := arg_nspecs + 1;
  END;
END;

PROCEDURE ArgFlag(long_name: ArgStr; short_name: CHAR; help: ArgStr);
BEGIN
  ArgAdd(long_name, short_name, help, ARG_KIND_FLAG);
END;

PROCEDURE ArgString(long_name: ArgStr; short_name: CHAR;
                    default_value: ArgStr; help: ArgStr);
BEGIN
  ArgAdd(long_name, short_name, help, ARG_KIND_STRING);
  IF arg_nspecs > 0 THEN
    ArgSetStr(arg_specs[arg_nspecs - 1].def_str, default_value);
END;

PROCEDURE ArgInt(long_name: ArgStr; short_name: CHAR;
                 default_value: INTEGER32; help: ArgStr);
BEGIN
  ArgAdd(long_name, short_name, help, ARG_KIND_INT);
  IF arg_nspecs > 0 THEN arg_specs[arg_nspecs - 1].def_int := default_value;
END;

PROCEDURE ArgReal(long_name: ArgStr; short_name: CHAR;
                  default_value: REAL; help: ArgStr);
BEGIN
  ArgAdd(long_name, short_name, help, ARG_KIND_REAL);
  IF arg_nspecs > 0 THEN arg_specs[arg_nspecs - 1].def_real := default_value;
END;

{ ------------------------------------------------------------------ }
{ Help                                                                }
{ ------------------------------------------------------------------ }

PROCEDURE ArgWriteStr(s: ArgStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := ORD(s[0]);
  i := 1;
  WHILE i <= n DO
  BEGIN
    WRITE(s[i]);
    i := i + 1;
  END;
END;

PROCEDURE ArgUsage;
VAR
  i, j, pad: INTEGER32;
BEGIN
  WRITE('Usage: ');
  ArgWriteStr(arg_prog);
  WRITELN(' [options]');
  IF ORD(arg_desc[0]) > 0 THEN
  BEGIN
    WRITELN;
    ArgWriteStr(arg_desc);
    WRITELN;
  END;
  WRITELN;
  WRITELN('Options:');
  i := 0;
  WHILE i < arg_nspecs DO
  BEGIN
    WRITE('  ');
    IF arg_specs[i].short_name <> ARG_NO_SHORT THEN
      WRITE('-', arg_specs[i].short_name, ', ')
    ELSE
      WRITE('    ');
    WRITE('--');
    ArgWriteStr(arg_specs[i].long_name);
    IF arg_specs[i].kind <> ARG_KIND_FLAG THEN WRITE(' <value>');
    { Pad to a column so the help text lines up. }
    pad := 26 - ORD(arg_specs[i].long_name[0]);
    IF arg_specs[i].kind <> ARG_KIND_FLAG THEN pad := pad - 8;
    j := 0;
    WHILE j < pad DO
    BEGIN
      WRITE(' ');
      j := j + 1;
    END;
    ArgWriteStr(arg_specs[i].help);
    WRITELN;
    i := i + 1;
  END;
  { --help is not a registered option, but its row is padded by the same rule
    as the others so the help column lines up. }
  WRITE('  -h, --help');
  pad := 26 - 4;
  j := 0;
  WHILE j < pad DO
  BEGIN
    WRITE(' ');
    j := j + 1;
  END;
  WRITELN('Show this help and exit.');
END;

{ ------------------------------------------------------------------ }
{ Parsing                                                             }
{ ------------------------------------------------------------------ }

{ Split "--name=value" at the first '='. Returns TRUE when one was found,
  with name and the argv offset of the character after it. }
FUNCTION ArgSplitEq(token: ArgStr; VAR name: ArgStr): INTEGER32;
VAR
  i, n, eq: INTEGER32;
BEGIN
  n := ORD(token[0]);
  eq := -1;
  i := 1;
  WHILE (i <= n) AND (eq < 0) DO
  BEGIN
    IF token[i] = '=' THEN eq := i;
    i := i + 1;
  END;
  IF eq < 0 THEN
    ArgSetStr(name, token)
  ELSE
  BEGIN
    name[0] := CHR(RETYPE(INTEGER, eq - 1));
    i := 1;
    WHILE i < eq DO
    BEGIN
      name[i] := token[i];
      i := i + 1;
    END;
  END;
  ArgSplitEq := eq;
END;

FUNCTION ArgFindShort(c: CHAR): INTEGER32;
VAR
  i, found: INTEGER32;
BEGIN
  found := -1;
  IF c <> ARG_NO_SHORT THEN
  BEGIN
    i := 0;
    WHILE (i < arg_nspecs) AND (found < 0) DO
    BEGIN
      IF arg_specs[i].short_name = c THEN found := i;
      i := i + 1;
    END;
  END;
  ArgFindShort := found;
END;

{ A pointer to the value part of an argv token that contained '='. argv memory
  outlives the process's use of it, so pointing into it is safe and avoids
  copying a value that may exceed 255 characters. }
FUNCTION ArgValueAfterEq(raw: ADRMEM; eq: INTEGER32): ADRMEM;
VAR
  base, p: ^CHAR;
BEGIN
  base := raw;
  p := base + eq;         { eq is 1-based over the LSTRING, so this is the
                            character just past '=' in the C string }
  ArgValueAfterEq := p;
END;

FUNCTION ArgParse: BOOLEAN;
VAR
  i, argc, eq, slot: INTEGER32;
  raw: ADRMEM;
  token, name: ArgStr;
  only_positional, needs_value: BOOLEAN;
BEGIN
  arg_npositional := 0;
  arg_help_wanted := FALSE;
  only_positional := FALSE;
  argc := pas_arg_count;
  i := 1;
  WHILE (i < argc) AND (NOT arg_have_error) AND (NOT arg_help_wanted) DO
  BEGIN
    raw := pas_arg_value(i);
    ArgCStrToStr(raw, token);
    IF only_positional THEN
    BEGIN
      IF arg_npositional < ARG_MAX_POSITIONAL THEN
      BEGIN
        arg_positional[arg_npositional] := raw;
        arg_npositional := arg_npositional + 1;
      END
      ELSE
        ArgFail('too many positional arguments at: ', token);
    END
    ELSE IF ArgStrEq(token, '--') THEN
      only_positional := TRUE
    ELSE IF ArgStrEq(token, '--help') OR ArgStrEq(token, '-h') THEN
    BEGIN
      arg_help_wanted := TRUE;
      ArgUsage;
    END
    ELSE IF (ORD(token[0]) >= 2) AND (token[1] = '-') THEN
    BEGIN
      eq := ArgSplitEq(token, name);
      IF token[2] = '-' THEN
      BEGIN
        ArgDropPrefix(name, 2);
        slot := ArgFind(name);
      END
      ELSE IF ORD(name[0]) = 2 THEN
        slot := ArgFindShort(name[2])
      ELSE
        slot := -1;

      IF slot < 0 THEN
        ArgFail('unrecognized option: ', token)
      ELSE
      BEGIN
        arg_specs[slot].given := TRUE;
        needs_value := arg_specs[slot].kind <> ARG_KIND_FLAG;
        IF NOT needs_value THEN
        BEGIN
          IF eq >= 0 THEN
            ArgFail('option takes no value: ', token)
          ELSE
            arg_specs[slot].flag_on := TRUE;
        END
        ELSE IF eq >= 0 THEN
          arg_specs[slot].value_ptr := ArgValueAfterEq(raw, eq)
        ELSE
        BEGIN
          i := i + 1;
          IF i >= argc THEN
            ArgFail('option requires a value: ', token)
          ELSE
            arg_specs[slot].value_ptr := pas_arg_value(i);
        END;
      END;
    END
    ELSE
    BEGIN
      IF arg_npositional < ARG_MAX_POSITIONAL THEN
      BEGIN
        arg_positional[arg_npositional] := raw;
        arg_npositional := arg_npositional + 1;
      END
      ELSE
        ArgFail('too many positional arguments at: ', token);
    END;
    i := i + 1;
  END;
  ArgParse := (NOT arg_have_error) AND (NOT arg_help_wanted);
END;

FUNCTION ArgHelpWanted: BOOLEAN;
BEGIN
  ArgHelpWanted := arg_help_wanted;
END;

PROCEDURE ArgError(VAR out: ArgStr);
BEGIN
  ArgSetStr(out, arg_error_msg);
END;

{ ------------------------------------------------------------------ }
{ Queries                                                             }
{ ------------------------------------------------------------------ }

FUNCTION ArgWasGiven(long_name: ArgStr): BOOLEAN;
VAR
  slot: INTEGER32;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgWasGiven := FALSE
  ELSE
    ArgWasGiven := arg_specs[slot].given;
END;

FUNCTION ArgGetFlag(long_name: ArgStr): BOOLEAN;
VAR
  slot: INTEGER32;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgGetFlag := FALSE
  ELSE
    ArgGetFlag := arg_specs[slot].flag_on;
END;

FUNCTION ArgGetRaw(long_name: ArgStr): ADRMEM;
VAR
  slot: INTEGER32;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgGetRaw := NIL
  ELSE IF arg_specs[slot].value_ptr <> NIL THEN
    ArgGetRaw := arg_specs[slot].value_ptr
  ELSE
    ArgGetRaw := ArgStrToCStr(arg_specs[slot].def_str);
END;

PROCEDURE ArgGetStr(long_name: ArgStr; VAR out: ArgStr);
VAR
  slot: INTEGER32;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgSetStr(out, '')
  ELSE IF arg_specs[slot].value_ptr <> NIL THEN
    ArgCStrToStr(arg_specs[slot].value_ptr, out)
  ELSE
    ArgSetStr(out, arg_specs[slot].def_str);
END;

FUNCTION ArgGetInt(long_name: ArgStr): INTEGER32;
VAR
  slot: INTEGER32;
  endp: ADRMEM;
  v: INTEGER64;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgGetInt := 0
  ELSE IF arg_specs[slot].value_ptr = NIL THEN
    ArgGetInt := arg_specs[slot].def_int
  ELSE
  BEGIN
    endp := NIL;
    v := strtol(arg_specs[slot].value_ptr, ADR endp, 10);
    ArgGetInt := RETYPE(INTEGER32, v);
  END;
END;

FUNCTION ArgGetReal(long_name: ArgStr): REAL;
VAR
  slot: INTEGER32;
  endp: ADRMEM;
BEGIN
  slot := ArgFind(long_name);
  IF slot < 0 THEN
    ArgGetReal := 0.0
  ELSE IF arg_specs[slot].value_ptr = NIL THEN
    ArgGetReal := arg_specs[slot].def_real
  ELSE
  BEGIN
    endp := NIL;
    ArgGetReal := strtod(arg_specs[slot].value_ptr, ADR endp);
  END;
END;

FUNCTION ArgPosCount: INTEGER32;
BEGIN
  ArgPosCount := arg_npositional;
END;

FUNCTION ArgPosRaw(i: INTEGER32): ADRMEM;
BEGIN
  IF (i < 0) OR (i >= arg_npositional) THEN
    ArgPosRaw := NIL
  ELSE
    ArgPosRaw := arg_positional[i];
END;

PROCEDURE ArgPosStr(i: INTEGER32; VAR out: ArgStr);
BEGIN
  IF (i < 0) OR (i >= arg_npositional) THEN
    ArgSetStr(out, '')
  ELSE
    ArgCStrToStr(arg_positional[i], out);
END;

BEGIN
END.
