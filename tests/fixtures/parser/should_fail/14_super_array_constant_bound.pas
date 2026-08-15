(* should_fail: super_array_type = "SUPER" "ARRAY" "[" constant ".." "*" "]" ...
   The upper bound MUST be "*"; a concrete constant bound is not permitted.
   Current parser ACCEPTS this (allow_star path falls through to a constant)
   -> known deviation. *)
PROGRAM P;
TYPE T = SUPER ARRAY [0..10] OF INTEGER;
BEGIN
END.
