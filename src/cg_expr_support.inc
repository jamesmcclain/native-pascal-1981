{ Leaf expression-lowering helpers.  This unit emits IR but never evaluates an
  AST node, so it remains below the expression dispatcher. }

INTERFACE;
UNIT cg_expr_support;
USES jsonutil, features, cg_base, cg_util, cg_types;

FUNCTION VariadicPromote(v: ADRMEM; tk: INTEGER; name: Str255): ADRMEM;
FUNCTION MakeArgs1(v: ADRMEM): ADRMEM;
FUNCTION CodegenHostDeviceIndex(nm: Str255): ADRMEM;
FUNCTION CodegenDeviceIndex(nm: Str255): ADRMEM;
FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;

END;
