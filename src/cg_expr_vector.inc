{ Lowering for VECTOR [n] OF scalar operations: elementwise arithmetic and
  logic, VSPLAT, horizontal reductions, comparisons/masks/VSELECT, and
  VLOAD/VSTORE. Sits between cg_expr_literals and cg_expr in the codegen
  unit DAG -- it lowers already-evaluated operands (like cg_expr_sets) and
  never inspects or recursively evaluates an AST node; cg_expr evaluates
  the operands and dispatches in here from CodegenBinOp / CodegenUnaryOp /
  the FuncCall builtin ladder. }

INTERFACE;
UNIT cg_expr_vector;
USES jsonutil, features, cg_base, cg_util, cg_types;

{ VSPLAT(x, V): every lane of vector type vec_tid set to x. The caller has
  already evaluated x to scalar_val (type scalar_tk) and resolved the
  vector type name to vec_tid; arg_node is x's AST node, for diagnostics. }
FUNCTION CodegenVSplat(scalar_val: ADRMEM; scalar_tk: INTEGER; vec_tid: INTEGER; arg_node: ADRMEM): ADRMEM;

{ Elementwise `l <op> r` where both operands are the same VECTOR type. The
  caller (cg_expr's CodegenBinOp) has already evaluated the operands and
  passes their tracked type ids; op is the parser opcode string ('PLUS',
  'MINUS', 'MUL', 'SLASH', 'DIV', 'MOD', 'AND', 'OR', 'XOR'). }
FUNCTION CodegenVectorBinOp(op: Str255; lval, rval: ADRMEM; lvec_tid, rvec_tid: INTEGER): ADRMEM;

{ Elementwise unary `-v` ('MINUS') or `NOT v` ('NOT'). }
FUNCTION CodegenVectorUnaryOp(op: Str255; v: ADRMEM; vec_tid: INTEGER): ADRMEM;

{ Horizontal reduction of one vector to a scalar: nm is 'VSUM' 'VPROD'
  'VMIN' 'VMAX' 'VANY' 'VALL'. The caller has already evaluated the operand
  to vec_val (its tracked tid is vec_tid). Emits an `llvm.vector.reduce.*`
  intrinsic call (declaration get-or-created in the module, name mangled
  with the vector type); float VSUM/VPROD are ordered (a start operand,
  no `reassoc`). Sets last_val_tk (the element kind, or TK_BOOLEAN for
  VANY/VALL). }
FUNCTION CodegenVReduce(nm: Str255; vec_val: ADRMEM; vec_tid: INTEGER): ADRMEM;

{ Lanewise comparison `l <op> r` of two same-type vectors -> a
  VECTOR [n] OF BOOLEAN mask (<n x i8> of 0/1). op is 'EQ' 'NEQ' 'LT' 'LE'
  'GT' 'GE'. The caller has evaluated the operands and passes their tids;
  it also computes the result mask tid (EnsureBoolVectorType). }
FUNCTION CodegenVectorCmp(op: Str255; lval, rval: ADRMEM; lvec_tid, rvec_tid: INTEGER): ADRMEM;

{ VSELECT(m, a, b): per lane, m's lane picks a's or b's. m is a
  VECTOR [n] OF BOOLEAN, a and b the same VECTOR [n] OF T; result is that
  T vector. All three operands are already evaluated. }
FUNCTION CodegenVSelect(mask_val, a_val, b_val: ADRMEM;
                        mask_tid, a_tid, b_tid: INTEGER): ADRMEM;

{ Address of element `idx` of an array, for VLOAD/VSTORE. arr_ptr is the
  array's storage address, arr_tid its TK_ARRAY tid; the result points at
  a scalar of the array's element type. Aborts unless the array element
  kind equals the vector's, and -- for a constant idx -- unless
  idx .. idx+n-1 is within the array's declared bounds. }
FUNCTION CodegenVectorEltPtr(arr_ptr: ADRMEM; arr_tid: INTEGER;
                             idx_val: ADRMEM; idx_tk: INTEGER;
                             vec_tid: INTEGER; idx_node: ADRMEM): ADRMEM;

{ VLOAD(arr, i, V): load lanes arr[i .. i+n-1] as vector type vec_tid, at
  scalar-element alignment (safe for any i). }
FUNCTION CodegenVLoad(arr_ptr: ADRMEM; arr_tid: INTEGER;
                      idx_val: ADRMEM; idx_tk: INTEGER;
                      vec_tid: INTEGER; idx_node: ADRMEM): ADRMEM;

{ VSTORE(arr, i, v): store vector v's lanes into arr[i .. i+n-1], at
  scalar-element alignment. }
PROCEDURE CodegenVStore(arr_ptr: ADRMEM; arr_tid: INTEGER;
                        idx_val: ADRMEM; idx_tk: INTEGER;
                        vec_val: ADRMEM; vec_tid: INTEGER; idx_node: ADRMEM);

END;
