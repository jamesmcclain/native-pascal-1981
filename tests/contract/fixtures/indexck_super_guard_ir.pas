{ DIALECT: extended }
{ Compile only: guard-presence probes; no invalid access is ever executed.
  Seven super-array subscripts: three checked (including one dead access),
  four unchecked under disabled snapshots, including one whose snapshot was
  captured before an in-expression disabling directive. }
PROGRAM indexck_super_guard_ir(OUTPUT);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P; i: INTEGER;
BEGIN
  i := 2;
  p^[i] := 1;              { default snapshot: NIL and bounds guards }
  IF FALSE THEN p^[7] := 2; { dead access: guards present, never run }
  {$INDEXCK-}
  p^[i] := 3;              { disabled snapshot: no guards }
  IF FALSE THEN p^[9] := 4; { still disabled; never run }
  {$INDEXCK+}
  p^[i] := 5;              { restored: both guards again }
  p^[{$INDEXCK-}i] := 6;  { snapshot captured before the directive }
  p^[i] := 7              { the in-expression directive applies here }
END.
