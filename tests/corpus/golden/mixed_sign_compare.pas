{ DIALECT: extended }
{ Relationals between an INTEGER-family and a WORD-family operand compare
  exact values: a negative signed operand is below every unsigned value,
  even one with the same bit pattern. Each row is
  <  <=  =  <>  >=  >  for "s op u", then for "u op s". }
PROGRAM MixedSignCompare(output);
VAR
  s8: INTEGER8; u8: WORD8;
  s16: INTEGER; u16: WORD;
  s32: INTEGER32; u32: WORD32;
  s64: INTEGER64; u64: WORD64;

PROCEDURE R(lt, le, eq, ne, ge, gt: BOOLEAN);
  PROCEDURE B(x: BOOLEAN);
  BEGIN
    IF x THEN WRITE('T') ELSE WRITE('F')
  END;
BEGIN
  B(lt); B(le); B(eq); B(ne); B(ge); B(gt); WRITE(' ')
END;

BEGIN
  s8 := -1; u8 := 255;
  R(s8 < u8, s8 <= u8, s8 = u8, s8 <> u8, s8 >= u8, s8 > u8);
  R(u8 < s8, u8 <= s8, u8 = s8, u8 <> s8, u8 >= s8, u8 > s8); WRITELN;
  s8 := 127; u8 := 128;
  R(s8 < u8, s8 <= u8, s8 = u8, s8 <> u8, s8 >= u8, s8 > u8); WRITELN;

  s16 := -1; u16 := 65535;
  R(s16 < u16, s16 <= u16, s16 = u16, s16 <> u16, s16 >= u16, s16 > u16);
  R(u16 < s16, u16 <= s16, u16 = s16, u16 <> s16, u16 >= s16, u16 > s16); WRITELN;
  s16 := 100; u16 := 40000;
  R(s16 < u16, s16 <= u16, s16 = u16, s16 <> u16, s16 >= u16, s16 > u16); WRITELN;
  s16 := 5; u16 := 5;
  R(s16 < u16, s16 <= u16, s16 = u16, s16 <> u16, s16 >= u16, s16 > u16); WRITELN;
  s16 := 7; u16 := 3;
  R(s16 < u16, s16 <= u16, s16 = u16, s16 <> u16, s16 >= u16, s16 > u16); WRITELN;

  s32 := -1; u32 := 4294967295;
  R(s32 < u32, s32 <= u32, s32 = u32, s32 <> u32, s32 >= u32, s32 > u32);
  R(u32 < s32, u32 <= s32, u32 = s32, u32 <> s32, u32 >= s32, u32 > s32); WRITELN;
  s32 := 2147483647; u32 := 2147483648;
  R(s32 < u32, s32 <= u32, s32 = u32, s32 <> u32, s32 >= u32, s32 > u32); WRITELN;

  s64 := -1; u64 := MAXINT64; u64 := u64 + MAXINT64 + 1;
  R(s64 < u64, s64 <= u64, s64 = u64, s64 <> u64, s64 >= u64, s64 > u64);
  R(u64 < s64, u64 <= s64, u64 = s64, u64 <> s64, u64 >= s64, u64 > s64); WRITELN;
  s64 := MAXINT64; u64 := MAXINT64; u64 := u64 + 1;
  R(s64 < u64, s64 <= u64, s64 = u64, s64 <> u64, s64 >= u64, s64 > u64); WRITELN;

  { Different widths: the narrower operand extends by its own signedness. }
  s16 := -1; u32 := 5;
  R(s16 < u32, s16 <= u32, s16 = u32, s16 <> u32, s16 >= u32, s16 > u32);
  R(u32 < s16, u32 <= s16, u32 = s16, u32 <> s16, u32 >= s16, u32 > s16); WRITELN;
  s32 := -1; u16 := 65535;
  R(s32 < u16, s32 <= u16, s32 = u16, s32 <> u16, s32 >= u16, s32 > u16); WRITELN;
  s32 := 65535;
  R(s32 < u16, s32 <= u16, s32 = u16, s32 <> u16, s32 >= u16, s32 > u16); WRITELN;
  s8 := -1; u64 := 0;
  R(s8 < u64, s8 <= u64, s8 = u64, s8 <> u64, s8 >= u64, s8 > u64); WRITELN;
  s64 := -1; u8 := 0;
  R(u8 < s64, u8 <= s64, u8 = s64, u8 <> s64, u8 >= s64, u8 > s64); WRITELN
END.
