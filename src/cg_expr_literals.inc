{ Leaf lowering for assignments from compile-time string literals. }

INTERFACE;
UNIT cg_expr_literals;
USES jsonutil, features, cg_base, cg_util, cg_types;

PROCEDURE CodegenLStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);
PROCEDURE CodegenStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);

END;
