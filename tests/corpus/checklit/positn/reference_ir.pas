{ DIALECT: vintage extended }
{ CHECK: call i16 @ }
{ CHECK: load i8, ptr }
{ CHECK: call i32 @positn_from( }
{ CHECK-ASSEMBLE: ir }
PROGRAM reference_ir;
{$INITCK-}
VAR s: LSTRING(4);
FUNCTION Mut: INTEGER;
BEGIN s := 'xy'; Mut := 1 END;
BEGIN s := 'abab'; WRITELN(POSITN('ab', s, Mut)) END.
