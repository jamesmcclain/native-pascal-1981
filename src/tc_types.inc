{ AST type-expression resolution for the native type checker. }

INTERFACE;
UNIT tc_types;
USES jsonutil, features, tc_base;

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
FUNCTION IsSuperTypeExpr(node: ADRMEM): BOOLEAN;
FUNCTION SemanticOrdinalBase(tk, aux: INTEGER): INTEGER;
FUNCTION SemanticBaseOfOrdinalType(node: ADRMEM): INTEGER;
FUNCTION SemanticSetBaseType(node: ADRMEM): INTEGER;
FUNCTION SemanticChildTypeNode(node: ADRMEM): ADRMEM;
FUNCTION FwdCachedType(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER): BOOLEAN;
FUNCTION JsonIntegerValue(node: ADRMEM): INTEGER64;
FUNCTION FoldConstInt(node: ADRMEM; VAR folded_value: INTEGER64): BOOLEAN;
PROCEDURE CheckConstByteDomain(node: ADRMEM);
VAR
  { Set by FoldArith; read by tc_expr's CheckFoldedOperation. }
  fold_overflowed, fold_overflow_negative: BOOLEAN;

END;
