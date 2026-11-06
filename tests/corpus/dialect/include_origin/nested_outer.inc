{ Included by nested.pas and nested_inner_error.pas; includes
  nested_inner.inc. }
(*$INCLUDE:'nested_inner.inc'*)
PROCEDURE SetAt(i: INTEGER);
BEGIN
  a[i] := i
END;
