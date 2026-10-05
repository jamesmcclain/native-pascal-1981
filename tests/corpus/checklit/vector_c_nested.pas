{ DIALECT: extended }
{ A VECTOR nested inside a [C] record/ARRAY parameter is legal (only a
  *bare* vector in a [C] signature is rejected). The enclosing aggregate --
  even one small enough to be COERCED into registers -- must classify
  MEMORY and pass byval: the vector-register ABI classes (SSEUP) are not
  implemented, and WalkTypeLeaves has no vector arm, so ClassifyAggregate
  short-circuits any vector-bearing aggregate to MEMORY
  (AggregateHasVectorLeaf). Regression guard: this used to reach the
  WalkTypeLeaves unsupported-type-in-C-aggregate internal error.
  CHECK patterns below carry no braces, since a close-brace ends a comment. }
{ CHECK: @sink_rec(ptr byval( }
{ CHECK: @sink_arr(ptr byval( }
{ CHECK: x i8> }
PROGRAM VCNested;
TYPE
  V2B = VECTOR [2] OF INTEGER8;              { 2 bytes }
  R   = RECORD f: V2B END;                   { 2 bytes -- COERCED size }
  A   = ARRAY [1..2] OF V2B;                 { 4 bytes -- COERCED size }
FUNCTION sink_rec(x: R): CINT [C]; EXTERN;
FUNCTION sink_arr(x: A): CINT [C]; EXTERN;
VAR
  r: R;
  a: A;
BEGIN
  r := r;
  a := a
END.
