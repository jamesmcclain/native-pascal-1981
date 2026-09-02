{ pretty81: a formatting stage for native-pascal-1981.

  Reads the same JSON AST stream the codegen stage consumes (typically
  after the typechecker, though the parser's untyped AST works too since
  this stage never looks at resolved_type) and re-emits canonical,
  comment-preserving Pascal source text on stdout, instead of compiling.

  This is a *canonicalizing* formatter, not a format-preserving one:
  identifier casing, numeric literal spelling, and whitespace are not
  retained by the AST (see the lexer/parser survey this was built from),
  so round-tripping through pretty81 changes cosmetic spelling even
  though it preserves structure and comments. Every ordinary comment
  (captured by the lexer as token trivia and relayed onto AST nodes by
  the parser -- see lexer.pas RecordComment / ps_base.pas
  CreateTriviaNode) is re-emitted; a comment that was originally on the
  same source line as its token collapses onto one printed comment line
  even if it spanned several stacked source comments (CollapseNewlines),
  and a trailing comment lands on the innermost node built just before
  its token was consumed, not necessarily the outermost enclosing
  statement (see the parser-relay commit for why).

  Not part of the self-hosting core: gen1..gen4 only bootstrap lexer/
  parser/typechecker/codegen against the out-of-repo Python reference.
  pretty81 is built once against the gen4 fixed point instead, the same
  way astcompare.pas and proxy.pas are, and so is free to use whatever
  the native toolchain accepts even where the Python reference lags. }

(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pretty81(input, output);

USES jsonutil;

FUNCTION cJSON_IsString(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

VAR
  indent_level: INTEGER;

{ ============================ small helpers =============================== }

FUNCTION Join(left, right: Str255): Str255;
VAR
  result: Str255;
  i, left_len, right_len: INTEGER;
BEGIN
  left_len := ORD(left[0]);
  right_len := ORD(right[0]);
  IF left_len + right_len > 255 THEN right_len := 255 - left_len;
  result[0] := CHR(left_len + right_len);
  FOR i := 1 TO left_len DO result[i] := left[i];
  FOR i := 1 TO right_len DO result[left_len + i] := right[i];
  Join := result;
END;

FUNCTION Ch(c: CHAR): Str255;
{ A single-quoted single-character literal lexes as CHAR in this dialect,
  not a 1-character Str255, so Join needs this wrapper wherever the source
  spells a bare CHAR literal ('.', '-', a lone quote via ''''). }
VAR r: Str255;
BEGIN
  r[0] := CHR(1);
  r[1] := c;
  Ch := r;
END;

FUNCTION QuoteCharLiteral(v: Str255): Str255;
{ Unlike StringLiteral.value (the pre-quoted source lexeme, see
  PrintExpr's CharLiteral/StringLiteral branch), CharLiteral.value is the
  raw *decoded* single character (CurValueStr in ps_expr.pas's
  ParseConstant) -- it still needs quote-wrapping, with the one-character
  '' -> '''''' doubling if that character is itself a quote. Built from
  CHR(39) rather than a quote literal in the source, to sidestep this
  dialect's own single-quoted-single-character-is-CHAR-not-Str255 rule
  entirely (see Ch above). }
VAR
  r: Str255;
  q: CHAR;
BEGIN
  q := CHR(39);
  IF (ORD(v[0]) >= 1) AND (v[1] = q) THEN
  BEGIN
    r[0] := CHR(4);
    r[1] := q; r[2] := q; r[3] := q; r[4] := q;
  END
  ELSE
  BEGIN
    r[0] := CHR(3);
    r[1] := q;
    IF ORD(v[0]) >= 1 THEN r[2] := v[1] ELSE r[2] := ' ';
    r[3] := q;
  END;
  QuoteCharLiteral := r;
END;

FUNCTION IsPresent(item: ADRMEM): BOOLEAN;
{ GetObj on an optional field whose JSON value is `null` (rather than the
  key being absent) returns a real cJSON node wrapping that null, not a C
  NULL -- so "<> NIL" alone never detects the field's absence. Every
  optional-node field (WriteArg width/precision, IfStmt else_branch,
  CaseStmt otherwise, a DEREF selector, ...) must be checked with this
  instead. }
BEGIN
  IsPresent := (item <> NIL) AND (cJSON_IsNull(item) = 0);
END;

FUNCTION IntToStr(number: INTEGER32): Str255;
VAR
  result, reversed: Str255;
  digit, count, i: INTEGER;
  work: INTEGER32;
  neg: BOOLEAN;
BEGIN
  neg := number < 0;
  IF neg THEN work := -number ELSE work := number;
  IF work = 0 THEN
  BEGIN
    result[0] := CHR(1);
    result[1] := '0';
  END
  ELSE
  BEGIN
    count := 0;
    WHILE work > 0 DO
    BEGIN
      count := count + 1;
      digit := RETYPE(INTEGER, work - (work DIV 10) * 10);
      reversed[count] := CHR(ORD('0') + digit);
      work := work DIV 10;
    END;
    result[0] := CHR(count);
    FOR i := 1 TO count DO result[i] := reversed[count - i + 1];
  END;
  IF neg THEN result := Join(Ch('-'), result);
  IntToStr := result;
END;

FUNCTION RealToStr(rv: REAL): Str255;
{ Canonical decimal rendering, 6 fractional digits with trailing zeros
  trimmed (but at least one kept -- Pascal REAL literals require a digit
  after the point). Numeric spelling is already lossy in this AST (the
  lexer/parser normalize literal text away), so this is a fresh rendering,
  not a reconstruction. }
VAR
  neg: BOOLEAN;
  whole: INTEGER32;
  frac: REAL;
  digits, result: Str255;
  i, keep: INTEGER;
  d: INTEGER;
BEGIN
  neg := rv < 0.0;
  IF neg THEN rv := -rv;
  whole := TRUNC(rv);
  frac := rv - whole;
  digits[0] := CHR(6);
  FOR i := 1 TO 6 DO
  BEGIN
    frac := frac * 10.0;
    d := TRUNC(frac);
    IF d > 9 THEN d := 9;
    digits[i] := CHR(ORD('0') + d);
    frac := frac - d;
  END;
  keep := 6;
  WHILE (keep > 1) AND (digits[keep] = '0') DO keep := keep - 1;
  digits[0] := CHR(keep);
  result := Join(Join(IntToStr(whole), Ch('.')), digits);
  IF neg THEN result := Join(Ch('-'), result);
  RealToStr := result;
END;

FUNCTION CollapseNewlines(s: Str255): Str255;
VAR
  i: INTEGER;
  r: Str255;
BEGIN
  r[0] := s[0];
  FOR i := 1 TO ORD(s[0]) DO
    IF s[i] = CHR(10) THEN r[i] := ' ' ELSE r[i] := s[i];
  CollapseNewlines := r;
END;

FUNCTION OpSymbol(op: Str255): Str255;
{ BinOp/UnaryOp.op stores the raw token-kind name (e.g. 'GT', 'MINUS'),
  not a printable operator spelling -- map the symbolic ones back to
  Pascal syntax; word operators (AND/OR/DIV/MOD/IN/NOT) are already their
  own spelling and pass through the ELSE arm unchanged. }
BEGIN
  IF op = 'EQ' THEN OpSymbol := Ch('=')
  ELSE IF op = 'NEQ' THEN OpSymbol := '<>'
  ELSE IF op = 'LT' THEN OpSymbol := Ch('<')
  ELSE IF op = 'LE' THEN OpSymbol := '<='
  ELSE IF op = 'GT' THEN OpSymbol := Ch('>')
  ELSE IF op = 'GE' THEN OpSymbol := '>='
  ELSE IF op = 'PLUS' THEN OpSymbol := Ch('+')
  ELSE IF op = 'MINUS' THEN OpSymbol := Ch('-')
  ELSE IF op = 'MUL' THEN OpSymbol := Ch('*')
  ELSE IF op = 'SLASH' THEN OpSymbol := Ch('/')
  ELSE IF op = 'AND_THEN' THEN OpSymbol := 'AND THEN'
  ELSE IF op = 'OR_ELSE' THEN OpSymbol := 'OR ELSE'
  ELSE OpSymbol := op;
END;

PROCEDURE Out(s: Str255);
{ codegen's WRITE only takes an LSTRING argument when it is a bare
  Identifier/Designator (something addressable) -- a function-call
  expression returning Str255 by value falls through to the scalar path
  and aborts ("unsupported WRITE argument type"). Every print call in this
  file routes through here (and OutLn below) so the WRITE the compiler
  actually sees is always of a local variable. }
VAR tmp: Str255;
BEGIN
  tmp := s;
  WRITE(tmp);
END;

PROCEDURE OutLn(s: Str255);
VAR tmp: Str255;
BEGIN
  tmp := s;
  WRITELN(tmp);
END;

PROCEDURE Ind;
VAR i: INTEGER;
BEGIN
  FOR i := 1 TO indent_level DO Out('  ');
END;

FUNCTION CapLen(s: Str255; maxlen: INTEGER): Str255;
VAR r: Str255;
BEGIN
  r := s;
  IF ORD(r[0]) > maxlen THEN r[0] := CHR(maxlen);
  CapLen := r;
END;

PROCEDURE PrintLeadingComments(node: ADRMEM);
{ Join caps every result at 255 chars by silently dropping the tail of its
  right-hand operand -- since the comment-delimiter wrapper is applied by
  nesting Join calls, a comment body long enough to already fill the cap
  on its own drops the closing delimiter with no error, leaving an
  unterminated comment that swallows the rest of the file on reparse. Cap
  the raw text first, leaving room for the wrapper's own characters. }
VAR
  arr, item: ADRMEM;
  n, i: INTEGER32;
BEGIN
  IF HasKey(node, 'leading_comments') THEN
  BEGIN
    arr := GetObj(node, 'leading_comments');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      item := ArrItem(arr, i);
      Ind;
      OutLn(Join(Join('{ ', CapLen(CollapseNewlines(CStrToStr255(cJSON_GetStringValue(item))), 251)), ' }'));
    END;
  END;
END;

PROCEDURE PrintTrailingComment(node: ADRMEM);
BEGIN
  IF HasKey(node, 'trailing_comment') THEN
    Out(Join(Join(' { ', CapLen(CollapseNewlines(GetStr(node, 'trailing_comment')), 250)), ' }'));
END;

{ ============================ forward declarations ========================= }

PROCEDURE PrintDecl(node: ADRMEM); FORWARD;
PROCEDURE PrintDeclList(arr: ADRMEM); FORWARD;
PROCEDURE PrintStmt(node: ADRMEM); FORWARD;
PROCEDURE PrintCompoundBody(stmts: ADRMEM); FORWARD;
PROCEDURE PrintExpr(node: ADRMEM); FORWARD;
PROCEDURE PrintType(node: ADRMEM); FORWARD;
PROCEDURE PrintParams(arr: ADRMEM); FORWARD;
PROCEDURE PrintUses(arr: ADRMEM); FORWARD;
PROCEDURE PrintRecordFields(arr: ADRMEM); FORWARD;
PROCEDURE PrintBlock(node: ADRMEM); FORWARD;
PROCEDURE PrintInterfaceUnit(node: ADRMEM); FORWARD;

{ ================================ expressions =============================== }

PROCEDURE PrintExpr(node: ADRMEM);
VAR
  nt: Str255;
  arr, item, tgt: ADRMEM;
  n, i: INTEGER32;
BEGIN
  nt := NodeType(node);
  IF nt = 'Identifier' THEN
    Out(GetStr(node, 'name'))
  ELSE IF nt = 'IntLiteral' THEN
    Out(IntToStr(GetInt(node, 'value')))
  ELSE IF nt = 'RealLiteral' THEN
    Out(RealToStr(GetReal(node, 'value')))
  ELSE IF nt = 'StringLiteral' THEN
    { .value is already the raw quoted+escaped source lexeme (see
      lexer.pas ScanString's lexeme-vs-str_val split and ps_expr.pas
      ParseConstant, which stores CurLex here, not the decoded value). }
    Out(GetStr(node, 'value'))
  ELSE IF nt = 'CharLiteral' THEN
    Out(QuoteCharLiteral(GetStr(node, 'value')))
  ELSE IF nt = 'BoolLiteral' THEN
  BEGIN
    IF GetBool(node, 'value') THEN Out('TRUE') ELSE Out('FALSE');
  END
  ELSE IF nt = 'NilLiteral' THEN
    Out('NIL')
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    Out(Ch('('));
    PrintExpr(GetObj(node, 'left'));
    Out(Ch(' ')); Out(OpSymbol(GetStr(node, 'op'))); Out(Ch(' '));
    PrintExpr(GetObj(node, 'right'));
    Out(Ch(')'));
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    Out(Ch('(')); Out(OpSymbol(GetStr(node, 'op'))); Out(Ch(' '));
    PrintExpr(GetObj(node, 'operand'));
    Out(Ch(')'));
  END
  ELSE IF nt = 'Designator' THEN
  BEGIN
    Out(GetStr(node, 'name'));
    arr := GetObj(node, 'selectors');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      item := ArrItem(arr, i);
      tgt := GetObj(item, 'index_or_field');
      IF NOT IsPresent(tgt) THEN
        Out(Ch('^'))
      ELSE IF cJSON_IsString(tgt) <> 0 THEN
      BEGIN
        Out(Ch('.')); Out(CStrToStr255(cJSON_GetStringValue(tgt)));
      END
      ELSE
      BEGIN
        Out(Ch('[')); PrintExpr(tgt); Out(Ch(']'));
      END;
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    Out(GetStr(node, 'name'));
    arr := GetObj(node, 'args');
    n := ArrSize(arr);
    IF n > 0 THEN
    BEGIN
      Out(Ch('('));
      FOR i := 0 TO n - 1 DO
      BEGIN
        IF i > 0 THEN Out(', ');
        item := ArrItem(arr, i);
        IF NodeType(item) = 'WriteArg' THEN
        BEGIN
          PrintExpr(GetObj(item, 'expr'));
          IF IsPresent(GetObj(item, 'width')) THEN
          BEGIN Out(Ch(':')); PrintExpr(GetObj(item, 'width')); END;
          IF IsPresent(GetObj(item, 'precision')) THEN
          BEGIN Out(Ch(':')); PrintExpr(GetObj(item, 'precision')); END;
        END
        ELSE
          PrintExpr(item);
      END;
      Out(Ch(')'));
    END;
  END
  ELSE IF nt = 'RangeExpr' THEN
  BEGIN
    PrintExpr(GetObj(node, 'low')); Out('..'); PrintExpr(GetObj(node, 'high'));
  END
  ELSE IF nt = 'SetConstructor' THEN
  BEGIN
    Out(Ch('['));
    arr := GetObj(node, 'elements');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      PrintExpr(ArrItem(arr, i));
    END;
    Out(Ch(']'));
  END
  ELSE IF nt = 'RetypeExpr' THEN
  BEGIN
    Out('RETYPE('); Out(GetStr(node, 'type_id')); Out(', ');
    PrintExpr(GetObj(node, 'expr')); Out(Ch(')'));
  END
  ELSE IF nt = 'SizeofExpr' THEN
  BEGIN
    Out('SIZEOF(');
    tgt := GetObj(node, 'target');
    IF cJSON_IsString(tgt) <> 0 THEN Out(CStrToStr255(cJSON_GetStringValue(tgt)))
    ELSE PrintType(tgt);
    Out(Ch(')'));
  END
  ELSE IF nt = 'AdrExpr' THEN
  BEGIN
    Out('ADR '); Out(GetStr(node, 'name'));
  END
  ELSE IF nt = 'LowerExpr' THEN
  BEGIN
    Out('LOWER(');
    IF GetBool(node, 'deref') THEN Out(Ch('^'));
    Out(GetStr(node, 'name')); Out(Ch(')'));
  END
  ELSE IF nt = 'UpperExpr' THEN
  BEGIN
    Out('UPPER(');
    IF GetBool(node, 'deref') THEN Out(Ch('^'));
    Out(GetStr(node, 'name')); Out(Ch(')'));
  END
  ELSE
  BEGIN
    Out('(* pretty81: unhandled expr '); Out(nt); Out(' *)');
  END;
END;

{ ================================== types ==================================== }

PROCEDURE PrintType(node: ADRMEM);
VAR
  nt: Str255;
  arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  nt := NodeType(node);
  IF nt = 'BuiltinType' THEN
    Out(GetStr(node, 'name'))
  ELSE IF nt = 'NamedType' THEN
  BEGIN
    Out(GetStr(node, 'name'));
    IF GetStr(node, 'param') <> '' THEN
    BEGIN Out(Ch('(')); Out(GetStr(node, 'param')); Out(Ch(')')); END;
  END
  ELSE IF nt = 'ArrayType' THEN
  BEGIN
    IF GetBool(node, 'packed') THEN Out('PACKED ');
    Out('ARRAY['); PrintType(GetObj(node, 'index_range')); Out('] OF ');
    PrintType(GetObj(node, 'element_type'));
  END
  ELSE IF nt = 'IndexRange' THEN
  BEGIN
    PrintExpr(GetObj(node, 'low'));
    IF IsPresent(GetObj(node, 'high')) THEN
    BEGIN Out('..'); PrintExpr(GetObj(node, 'high')); END;
  END
  ELSE IF nt = 'RecordType' THEN
  BEGIN
    IF GetBool(node, 'packed') THEN Out('PACKED ');
    OutLn('RECORD');
    indent_level := indent_level + 1;
    PrintRecordFields(GetObj(node, 'fields'));
    indent_level := indent_level - 1;
    Ind; Out('END');
  END
  ELSE IF nt = 'PointerType' THEN
  BEGIN
    Out(Ch('^')); PrintType(GetObj(node, 'base'));
  END
  ELSE IF nt = 'SubrangeType' THEN
  BEGIN
    PrintExpr(GetObj(node, 'low')); Out('..'); PrintExpr(GetObj(node, 'high'));
  END
  ELSE IF nt = 'EnumType' THEN
  BEGIN
    Out(Ch('('));
    arr := GetObj(node, 'values');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      Out(CStrToStr255(cJSON_GetStringValue(ArrItem(arr, i))));
    END;
    Out(Ch(')'));
  END
  ELSE IF nt = 'SetType' THEN
  BEGIN
    Out('SET OF '); PrintType(GetObj(node, 'base'));
  END
  ELSE IF nt = 'FileType' THEN
  BEGIN
    Out('FILE OF '); PrintType(GetObj(node, 'element_type'));
  END
  ELSE IF nt = 'VectorType' THEN
  BEGIN
    Out('VECTOR['); PrintExpr(GetObj(node, 'lanes')); Out('] OF ');
    PrintType(GetObj(node, 'element_type'));
  END
  ELSE
  BEGIN
    Out('(* pretty81: unhandled type '); Out(nt); Out(' *)');
  END;
END;

PROCEDURE PrintRecordFields(arr: ADRMEM);
{ Each element is a __tuple__ wrapper: items[0] = names (scalar[]),
  items[1] = the field type node. Not an ordinary node kind.

  KNOWN GAP: a record field is built by MakeTupleNode (ps_expr.pas), a bare
  cJSON object, never CreateTriviaNode -- it has no leading_comments or
  trailing_comment field to print even in principle. Worse, the field
  separator SEMICOLON is consumed by a raw pos := pos + 1 in ParseType's
  RECORD branch (ps_expr.pas), which never calls RelayTokenTrivia, so a
  comment trailing a record field is silently dropped by the parser, not
  merely misattached -- it never reaches pretty81's input at all. Fixing
  this needs the field tuple to become trivia-capable and the separator
  to relay trivia like every other list-parsing loop, not just a change
  here. }
VAR
  n, i, j, names_n: INTEGER32;
  tup, items, names_arr, type_node: ADRMEM;
BEGIN
  n := ArrSize(arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    tup := ArrItem(arr, i);
    items := GetObj(tup, 'items');
    names_arr := ArrItem(items, 0);
    type_node := ArrItem(items, 1);
    Ind;
    names_n := ArrSize(names_arr);
    FOR j := 0 TO names_n - 1 DO
    BEGIN
      IF j > 0 THEN Out(', ');
      Out(CStrToStr255(cJSON_GetStringValue(ArrItem(names_arr, j))));
    END;
    Out(': '); PrintType(type_node); OutLn(Ch(';'));
  END;
END;

{ ================================ statements ================================= }

PROCEDURE PrintCompoundBody(stmts: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := ArrSize(stmts);
  FOR i := 0 TO n - 1 DO
  BEGIN
    PrintStmt(ArrItem(stmts, i));
    OutLn(Ch(';'));
  END;
END;

PROCEDURE PrintStmt(node: ADRMEM);
VAR
  nt: Str255;
  arr, elt, item, constants: ADRMEM;
  n, i, cn, ci: INTEGER32;
BEGIN
  nt := NodeType(node);
  PrintLeadingComments(node);
  Ind;
  IF nt = 'CompoundStmt' THEN
  BEGIN
    OutLn('BEGIN');
    indent_level := indent_level + 1;
    PrintCompoundBody(GetObj(node, 'stmts'));
    indent_level := indent_level - 1;
    Ind; Out('END');
  END
  ELSE IF nt = 'AssignStmt' THEN
  BEGIN
    PrintExpr(GetObj(node, 'target')); Out(' := '); PrintExpr(GetObj(node, 'expr'));
  END
  ELSE IF nt = 'ProcCallStmt' THEN
  BEGIN
    Out(GetStr(node, 'name'));
    arr := GetObj(node, 'args');
    n := ArrSize(arr);
    IF n > 0 THEN
    BEGIN
      Out(Ch('('));
      FOR i := 0 TO n - 1 DO
      BEGIN
        IF i > 0 THEN Out(', ');
        item := ArrItem(arr, i);
        IF NodeType(item) = 'WriteArg' THEN
        BEGIN
          PrintExpr(GetObj(item, 'expr'));
          IF IsPresent(GetObj(item, 'width')) THEN
          BEGIN Out(Ch(':')); PrintExpr(GetObj(item, 'width')); END;
          IF IsPresent(GetObj(item, 'precision')) THEN
          BEGIN Out(Ch(':')); PrintExpr(GetObj(item, 'precision')); END;
        END
        ELSE
          PrintExpr(item);
      END;
      Out(Ch(')'));
    END;
  END
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    Out('IF '); PrintExpr(GetObj(node, 'cond')); OutLn(' THEN');
    indent_level := indent_level + 1;
    PrintStmt(GetObj(node, 'then_branch'));
    indent_level := indent_level - 1;
    IF IsPresent(GetObj(node, 'else_branch')) THEN
    BEGIN
      WRITELN; Ind; OutLn('ELSE');
      indent_level := indent_level + 1;
      PrintStmt(GetObj(node, 'else_branch'));
      indent_level := indent_level - 1;
    END;
  END
  ELSE IF nt = 'WhileStmt' THEN
  BEGIN
    Out('WHILE '); PrintExpr(GetObj(node, 'cond')); OutLn(' DO');
    indent_level := indent_level + 1;
    PrintStmt(GetObj(node, 'body'));
    indent_level := indent_level - 1;
  END
  ELSE IF nt = 'RepeatStmt' THEN
  BEGIN
    OutLn('REPEAT');
    indent_level := indent_level + 1;
    PrintCompoundBody(GetObj(node, 'body'));
    indent_level := indent_level - 1;
    Ind; Out('UNTIL '); PrintExpr(GetObj(node, 'cond'));
  END
  ELSE IF nt = 'ForStmt' THEN
  BEGIN
    Out('FOR '); Out(GetStr(node, 'var')); Out(' := ');
    PrintExpr(GetObj(node, 'start'));
    IF GetStr(node, 'direction') = 'DOWNTO' THEN Out(' DOWNTO ') ELSE Out(' TO ');
    PrintExpr(GetObj(node, 'end')); OutLn(' DO');
    indent_level := indent_level + 1;
    PrintStmt(GetObj(node, 'body'));
    indent_level := indent_level - 1;
  END
  ELSE IF nt = 'CaseStmt' THEN
  BEGIN
    Out('CASE '); PrintExpr(GetObj(node, 'expr')); OutLn(' OF');
    indent_level := indent_level + 1;
    arr := GetObj(node, 'elements');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      elt := ArrItem(arr, i);
      Ind;
      constants := GetObj(elt, 'constants');
      cn := ArrSize(constants);
      FOR ci := 0 TO cn - 1 DO
      BEGIN
        IF ci > 0 THEN Out(', ');
        PrintExpr(ArrItem(constants, ci));
      END;
      indent_level := indent_level + 1;
      OutLn(Ch(':'));
      PrintStmt(GetObj(elt, 'stmt'));
      OutLn(Ch(';'));
      indent_level := indent_level - 1;
    END;
    IF IsPresent(GetObj(node, 'otherwise')) THEN
    BEGIN
      { No semicolon after this one: the grammar parses OTHERWISE's
        statement and expects END right after it, not a SEMICOLON
        (ParseCaseStmt in ps_stmt.pas), unlike every case element above,
        which the parser accepts a trailing SEMICOLON before. }
      Ind; OutLn('OTHERWISE');
      indent_level := indent_level + 1;
      PrintStmt(GetObj(node, 'otherwise'));
      WRITELN;
      indent_level := indent_level - 1;
    END;
    indent_level := indent_level - 1;
    Ind; Out('END');
  END
  ELSE IF nt = 'WithStmt' THEN
  BEGIN
    Out('WITH ');
    arr := GetObj(node, 'targets');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      PrintExpr(ArrItem(arr, i));
    END;
    OutLn(' DO');
    indent_level := indent_level + 1;
    PrintStmt(GetObj(node, 'body'));
    indent_level := indent_level - 1;
  END
  ELSE IF nt = 'GotoStmt' THEN
  BEGIN
    Out('GOTO '); Out(GetStr(node, 'label'));
  END
  ELSE IF nt = 'LabelStmt' THEN
  BEGIN
    Out(GetStr(node, 'label')); OutLn(Ch(':'));
    PrintStmt(GetObj(node, 'stmt'));
  END
  ELSE IF nt = 'BreakStmt' THEN
    Out('BREAK')
  ELSE IF nt = 'CycleStmt' THEN
    Out('CYCLE')
  ELSE IF nt = 'ReturnStmt' THEN
    Out('RETURN')
  ELSE IF nt = 'EmptyStmt' THEN
    { nothing }
  ELSE
    Out(Join('(* pretty81: unhandled stmt ', Join(nt, ' *)')));
  PrintTrailingComment(node);
END;

{ ================================ declarations ================================ }

PROCEDURE PrintParams(arr: ADRMEM);
VAR
  n, i, j, names_n: INTEGER32;
  p, names_arr: ADRMEM;
BEGIN
  n := ArrSize(arr);
  IF n > 0 THEN
  BEGIN
    Out(Ch('('));
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out('; ');
      p := ArrItem(arr, i);
      IF GetStr(p, 'mode') <> '' THEN
      BEGIN Out(GetStr(p, 'mode')); Out(Ch(' ')); END;
      names_arr := GetObj(p, 'names');
      names_n := ArrSize(names_arr);
      FOR j := 0 TO names_n - 1 DO
      BEGIN
        IF j > 0 THEN Out(', ');
        Out(CStrToStr255(cJSON_GetStringValue(ArrItem(names_arr, j))));
      END;
      Out(': '); PrintType(GetObj(p, 'type_expr'));
    END;
    Out(Ch(')'));
  END;
END;

PROCEDURE PrintBlock(node: ADRMEM);
BEGIN
  PrintDeclList(GetObj(node, 'decls'));
  Ind; OutLn('BEGIN');
  indent_level := indent_level + 1;
  PrintCompoundBody(GetObj(node, 'body'));
  indent_level := indent_level - 1;
  Ind; Out('END');
END;

PROCEDURE PrintDecl(node: ADRMEM);
VAR
  nt: Str255;
  arr, names_arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  nt := NodeType(node);
  PrintLeadingComments(node);
  Ind;
  IF nt = 'VarDecl' THEN
  BEGIN
    names_arr := GetObj(node, 'names');
    n := ArrSize(names_arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      Out(CStrToStr255(cJSON_GetStringValue(ArrItem(names_arr, i))));
    END;
    Out(': '); PrintType(GetObj(node, 'type_expr')); Out(Ch(';'));
  END
  ELSE IF nt = 'ConstDecl' THEN
  BEGIN
    Out(GetStr(node, 'name')); Out(' = '); PrintExpr(GetObj(node, 'value')); Out(Ch(';'));
  END
  ELSE IF nt = 'TypeDecl' THEN
  BEGIN
    Out(GetStr(node, 'name')); Out(' = '); PrintType(GetObj(node, 'type_expr')); Out(Ch(';'));
  END
  ELSE IF nt = 'LabelDecl' THEN
  BEGIN
    Out('LABEL ');
    arr := GetObj(node, 'labels');
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      Out(CStrToStr255(cJSON_GetStringValue(ArrItem(arr, i))));
    END;
    Out(Ch(';'));
  END
  ELSE IF (nt = 'ProcDecl') OR (nt = 'FuncDecl') THEN
  BEGIN
    IF nt = 'ProcDecl' THEN Out('PROCEDURE ') ELSE Out('FUNCTION ');
    Out(GetStr(node, 'name'));
    PrintParams(GetObj(node, 'params'));
    IF nt = 'FuncDecl' THEN
    BEGIN Out(': '); PrintType(GetObj(node, 'return_type')); END;
    IF GetStr(node, 'directive') <> '' THEN
    BEGIN Out('; '); Out(GetStr(node, 'directive')); END;
    OutLn(Ch(';'));
    IF IsPresent(GetObj(node, 'body')) THEN
    BEGIN
      PrintBlock(GetObj(node, 'body'));
      Out(Ch(';'));
    END;
  END
  ELSE
    Out(Join('(* pretty81: unhandled decl ', Join(nt, ' *)')));
  PrintTrailingComment(node);
  WRITELN;
END;

FUNCTION SectionKeyword(nt: Str255): Str255;
{ VarDecl/ConstDecl/TypeDecl are grouped under one VAR/CONST/TYPE header in
  real Pascal syntax, but the AST stores them as one flat decls list with
  no section wrapper node -- PrintDeclList reconstructs the header whenever
  the section kind changes. ProcDecl/FuncDecl/LabelDecl need no header,
  each already opens with its own keyword. }
BEGIN
  IF nt = 'VarDecl' THEN SectionKeyword := 'VAR'
  ELSE IF nt = 'ConstDecl' THEN SectionKeyword := 'CONST'
  ELSE IF nt = 'TypeDecl' THEN SectionKeyword := 'TYPE'
  ELSE SectionKeyword := '';
END;

PROCEDURE PrintDeclList(arr: ADRMEM);
VAR
  n, i: INTEGER32;
  cur_section, want_section: Str255;
  item: ADRMEM;
BEGIN
  n := ArrSize(arr);
  cur_section := '';
  FOR i := 0 TO n - 1 DO
  BEGIN
    item := ArrItem(arr, i);
    want_section := SectionKeyword(NodeType(item));
    IF want_section <> cur_section THEN
    BEGIN
      IF cur_section <> '' THEN indent_level := indent_level - 1;
      IF want_section <> '' THEN
      BEGIN
        Ind; OutLn(want_section);
        indent_level := indent_level + 1;
      END;
      cur_section := want_section;
    END;
    PrintDecl(item);
  END;
  IF cur_section <> '' THEN indent_level := indent_level - 1;
END;

PROCEDURE PrintUses(arr: ADRMEM);
VAR
  n, i: INTEGER32;
  item: ADRMEM;
BEGIN
  n := ArrSize(arr);
  IF n > 0 THEN
  BEGIN
    Out('USES ');
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      item := ArrItem(arr, i);
      Out(GetStr(item, 'name'));
    END;
    OutLn(Ch(';'));
  END;
END;

{ ================================== top level ================================= }

PROCEDURE PrintIdentList(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := ArrSize(arr);
  IF n > 0 THEN
  BEGIN
    Out(Ch('('));
    FOR i := 0 TO n - 1 DO
    BEGIN
      IF i > 0 THEN Out(', ');
      Out(CStrToStr255(cJSON_GetStringValue(ArrItem(arr, i))));
    END;
    Out(Ch(')'));
  END;
END;

PROCEDURE PrintLocalInterfaces(node: ADRMEM);
{ A unit-family root's local_interfaces array holds a duplicate of each
  leading standalone INTERFACE block the parser spliced out of the same
  source file (parser.pas's interfaces_arr loop) -- re-emit each as its
  own INTERFACE unit ahead of the root so the file round-trips. }
VAR
  arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  arr := GetObj(node, 'local_interfaces');
  n := ArrSize(arr);
  FOR i := 0 TO n - 1 DO
    PrintInterfaceUnit(ArrItem(arr, i));
END;

PROCEDURE PrintProgram(node: ADRMEM);
BEGIN
  PrintLocalInterfaces(node);
  Out('PROGRAM '); Out(GetStr(node, 'name')); Out(Ch('('));
  Out('input, output'); OutLn(');');
  WRITELN;
  PrintUses(GetObj(node, 'uses'));
  PrintBlock(GetObj(node, 'block'));
  OutLn(Ch('.'));
END;

PROCEDURE PrintModuleUnit(node: ADRMEM);
BEGIN
  PrintLocalInterfaces(node);
  IF GetBool(node, 'is_device') THEN Out('DEVICE ');
  Out('MODULE '); Out(GetStr(node, 'name')); OutLn(Ch(';'));
  WRITELN;
  PrintUses(GetObj(node, 'uses'));
  PrintDeclList(GetObj(node, 'decls'));
  OutLn('END.');
END;

PROCEDURE PrintInterfaceUnit(node: ADRMEM);
BEGIN
  IF GetBool(node, 'is_device') THEN Out('DEVICE ');
  OutLn('INTERFACE;');
  WRITELN;
  Out('UNIT '); Out(GetStr(node, 'name'));
  PrintIdentList(GetObj(node, 'params'));
  OutLn(Ch(';'));
  WRITELN;
  PrintUses(GetObj(node, 'uses'));
  PrintDeclList(GetObj(node, 'decls'));
  { An INTERFACE unit carries no runtime -- BEGIN..END here is only the
    1981-manual's alternate terminator spelling for "the interface section
    is done" (docs/ebnf_grammar.md), not an executable block, so the parser
    never stores its statements (and rejects it outright if it isn't
    empty). has_init just records which terminator spelling was used. }
  IF GetBool(node, 'has_init') THEN
    OutLn('BEGIN END;')
  ELSE
    OutLn('END;');
  WRITELN;
END;

PROCEDURE PrintImplementationUnit(node: ADRMEM);
BEGIN
  PrintLocalInterfaces(node);
  IF GetBool(node, 'is_device') THEN Out('DEVICE ');
  Out('IMPLEMENTATION OF '); Out(GetStr(node, 'name')); OutLn(Ch(';'));
  WRITELN;
  PrintUses(GetObj(node, 'uses'));
  PrintDeclList(GetObj(node, 'decls'));
  { ParseImplementationUnit requires DOT directly after decls when no init
    block was written -- there is no bare END in that case, unlike
    ProgramUnit/ModuleUnit where END is always emitted (or optional). }
  IF IsPresent(GetObj(node, 'init_body')) THEN
  BEGIN
    Ind; OutLn('BEGIN');
    indent_level := indent_level + 1;
    PrintCompoundBody(GetObj(node, 'init_body'));
    indent_level := indent_level - 1;
    Ind; OutLn('END.');
  END
  ELSE
    OutLn(Ch('.'));
END;

VAR
  root: ADRMEM;
  top_nt: Str255;

BEGIN
  indent_level := 0;
  root := ReadAllStdin;
  IF root = NIL THEN
  BEGIN
    EPrint('pretty81: failed to read AST from stdin');
    exit(1);
  END;
  top_nt := NodeType(root);
  IF top_nt = 'ProgramUnit' THEN
    PrintProgram(root)
  ELSE IF top_nt = 'ModuleUnit' THEN
    PrintModuleUnit(root)
  ELSE IF top_nt = 'InterfaceUnit' THEN
    PrintInterfaceUnit(root)
  ELSE IF top_nt = 'ImplementationUnit' THEN
    PrintImplementationUnit(root)
  ELSE
  BEGIN
    EPrintC(MakeCStr(Join('pretty81: unsupported top-level unit kind ', top_nt)));
    exit(1);
  END;
END.
