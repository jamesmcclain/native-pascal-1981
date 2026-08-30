{ DIALECT: extended }
{ A [VARARGS] [C] routine gets a genuinely variadic LLVM function type, and
  each tail argument carries C's default argument promotions: a narrow
  signed integer sign-extends, a WORD zero-extends, a REAL32 widens to
  double. These are exactly the instructions clang emits for the equivalent
  C variadic call. }
{ CHECK: declare i32 @snprintf(ptr, i64, ptr, ...) }
{ CHECK: sext i8 }
{ CHECK: zext i16 }
{ CHECK: fpext float }
{ CHECK: to double }
{ CHECK: call i32 (ptr, i64, ptr, ...) @snprintf }
PROGRAM VarargsCheck(output);
FUNCTION snprintf(dst: ADRMEM; sz: INTEGER64; fmt: ADRMEM): CINT [C, VARARGS]; EXTERN;
VAR
  buf, fmt: ADRMEM;
  n: CINT;
  small: INTEGER8;
  big_word: WORD;
  frac: REAL32;
BEGIN
  small := -7;
  big_word := 60000;
  frac := 2.5;
  n := snprintf(buf, 256, fmt, small, big_word, frac);
END.
